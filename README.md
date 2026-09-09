# SessionReplica Demo

**A phone-sized replica of a running coding-agent session — with a slider that makes the network hostile.**

Most resilience code is invisible: you write the retry logic, ship it, and hope. This app makes it visible. Drag the drop rate to 25%, turn on reordering, disconnect the link, teleport the session to a new epoch — and watch the transcript still end up byte-identical to the server's, with a metrics tab showing exactly how many duplicates were absorbed, how many gaps closed, and how many events the UI actually rendered per publish.

It consumes **[session-replica-kit](https://github.com/rajatslakhina/session-replica-kit)** as a version-pinned remote Swift package.

---

## Why this matters

You cannot review a resilience claim by reading it. "Handles reconnects" is not a fact until you have watched a reconnect happen and checked what the client did with the replayed events.

So this app exposes the failure modes as controls:

| Control | The bug it reproduces |
|---|---|
| **Drop 0–50%** | Gaps in the sequence. The replica must resync rather than render a transcript with holes in it. |
| **Duplicate 0–50%** | Replayed events after a reconnect. The classic symptom is a tool result rendered twice. |
| **Reorder window 1–8** | Parallel tool calls arriving interleaved, results before their own starts. |
| **Disconnect after 25 frames** | Resume from the cursor rather than starting over — the bug that blows the prompt cache. |
| **Stall (heartbeats only)** | The link that is neither alive nor dead. Watch the status bar go **Degraded — status only**, then recover via a snapshot instead of hanging. |
| **Teleport (new epoch)** | A restarted session whose sequence line starts over. Appending it to the old transcript is the `/teleport` bug. |
| **Compact the server log** | The cursor the relay can no longer replay from: base snapshot, then the log. (The control appends a turn *before* compacting — a caught-up replica's cursor is still servable, so compaction alone would visibly do nothing.) |
| **Agent machine offline** | Send a Stop and watch it sit at **queued — machine offline** instead of claiming "delivered". |

The **Metrics** tab shows the exactly-once counters live, and runs the library's independent invariant checker over the replica's own journal — a **PASS/FAIL verdict re-derived from what the replica did**, not from the code that did it.

## What the four tabs show

- **Session** — the streaming transcript: assistant text coalesced from deltas, parallel tool calls with per-call status, a `resultBeforeStart` placeholder when a result outruns its start, and an orange banner naming every field the server corrected on the last resync. The composer's draft survives every reconnect (client-owned); "Request mode" sends a command and the mode does **not** change until the server confirms it.
- **Chaos** — the controls above.
- **Outbox** — every command with its real state: `queued locally` → `in flight` → `forwarded, awaiting agent` / `queued — machine offline` → `acknowledged`. Two of those are explicitly non-terminal.
- **Metrics** — received / applied / duplicates dropped / buffered / gaps closed, reconnects, resyncs, snapshots, events-per-publish, and the invariant verdict.

## How to run it

```bash
git clone https://github.com/rajatslakhina/session-replica-demo-app.git
cd session-replica-demo-app
open Demo.xcodeproj
```

Then select the **Demo** scheme, pick any iOS Simulator, and Build & Run. Xcode resolves `session-replica-kit` from GitHub on first open — no local checkout of the library is needed and none is referenced.

Launch straight into a network condition with `-chaos`:

```
-chaos hostile      # drops + duplicates + reordering + a disconnect
-chaos drops        # 25% loss
-chaos duplicates   # 40% duplication
-chaos reorder      # reorder window of 6
-chaos stall        # heartbeats only after 14 frames
-chaos disconnect   # drop the link after 20 frames
```

(Edit Scheme → Run → Arguments. Absent or unrecognised, the link is clean.)

**A note on what "Reconnect" does.** It stops the run loop, drops the link, and starts a fresh one, leaving the view observer alone. In `1.0.0` that was load-bearing for a bad reason: `replica.views` was a single stored `AsyncStream`, and cancelling its consumer finishes the stream itself, so cancelling on reconnect froze the UI on its last frame while the replica kept running invisibly. The second review round replaced it — `views` now vends an independent stream per read — so the hazard is gone, but the observer is still started once and kept for the model's lifetime, because churning subscriptions on every reconnect buys nothing. `stop()` and `shutDown()` remain separate methods.

## The dependency is deliberately remote and version-pinned

`Demo.xcodeproj` references the library as an `XCRemoteSwiftPackageReference` at `https://github.com/rajatslakhina/session-replica-kit.git`, pinned `upToNextMajorVersion` from **2.0.0**. Not a local path — so the project genuinely resolves for anyone who clones it. Not `branch = main` either: branch-tracking means every clone and every CI run resolves whatever `main` happens to be that day, which is the wrong default for something meant to be reproducible.

For the same reason `Package.resolved` is **committed** rather than ignored, at `Demo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, pinning revision `fe86414`. `upToNextMajorVersion` alone still lets two clones resolve different 2.x versions; the lockfile is what makes a build reproducible, and for an application repo (as opposed to a library) it belongs in git. CI's `Show resolved version` step prints it, so if the committed file were ever wrong or missing the build would say so rather than quietly re-resolving.

The app imports **both** products for a real reason: `SessionReplicaUI` provides the screen, and `SessionReplica` is used directly by `DemoApp.swift`, which owns the three things the library deliberately does not decide — which session to replicate, the phone-shaped policy numbers (a smaller reorder window and tighter publish budget than the library defaults), and the `-chaos` launch-argument harness.

## Verification — exactly what did and did not happen

Stated as separate facts, because they are separate facts:

- **Compiles for an iOS Simulator: CI decides, and its verdict is on the [Actions](../../actions) tab — not asserted here.** The workflow does two things: `xcodebuild -resolvePackageDependencies`, which proves the remote package genuinely resolves from GitHub at the pinned version rather than from a local checkout, and then `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'`, which compiles `DemoApp.swift` against it. This bullet deliberately does not claim a result the run had not yet reported when it was written.
- **Was launched and run on a Simulator: no.** This project was produced by an unattended scheduled task, which cannot obtain screen-control permission. Access was requested three times and refused every time: the first attempt returned `You requested access to a terminal or IDE. It is rare for this to be required: these applications can only ever be granted in 'click' mode`, and each subsequent attempt returned `MCP server "computer-use" tool "request_access" timed out after 180s`. A closing `list_granted_applications` returned `{"allowedApps":[],...}`, confirming nothing was granted.
- **Screenshots: none exist.** There is deliberately no `Demo/Screenshots/` directory. No image in this README is described or implied, because there is no image to describe.
- **The library itself is verified independently and thoroughly:** `swift build -Xswiftc -warnings-as-errors` from a clean tree with zero warnings, and **120/120 tests passing** on Swift 6.0.3 — including chaos tests that assert the replica's transcript converges to byte-equality with the server's under drops, duplicates, reordering, stalls, disconnects, epoch changes and log compaction, and two rounds of independent adversarial review whose eleven findings are described in that repo's README rather than quietly amended. See the [library repo](https://github.com/rajatslakhina/session-replica-kit).

"Compiles for a Simulator" is a weaker claim than "ran on a Simulator", and this README does not let the first stand in for the second.

## License

MIT — see [LICENSE](LICENSE).
