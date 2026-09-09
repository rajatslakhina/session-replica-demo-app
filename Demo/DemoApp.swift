import SwiftUI
import SessionReplica
import SessionReplicaUI

/// The demo app owns three things the library deliberately does not decide:
///
/// 1. **The session it replicates.** `SessionReplica` is transport-agnostic;
///    something has to choose a server. Here it is the library's own
///    `ScriptedSessionServer` behind a `ChaosTransport`, so the app is
///    runnable with no backend — but the app, not the library, wires it up.
/// 2. **The policy numbers.** Reorder window, gap ceiling, heartbeat
///    timeouts, publish thresholds: every one is a product trade-off between
///    memory, latency and how long you are willing to look stalled. The
///    library ships defaults; a real app tunes them per platform.
/// 3. **The launch-argument harness.** `-chaos` with one of `clean`,
///    `hostile`, `drops`, `duplicates`, `reorder`, `stall` or `disconnect`
///    lets a UI test, a CI job or an agent driving the simulator start the
///    app straight into a specific network condition.
@main
struct DemoApp: App {
    private let model: SessionReplicaDemoModel

    init() {
        // Phone-shaped policy: a smaller reorder window than the library
        // default (memory is tighter than on desktop), a tighter publish
        // budget (120 Hz displays punish over-publishing), and a supervisor
        // that gives a cellular link a few seconds before calling it dead.
        let configuration = ReplicaConfiguration(
            ingest: IngestPolicy(maxReorderWindow: 32, maxGapWidth: 128),
            transcript: TranscriptPolicy(maxOrphanResults: 16, maxEntries: 500),
            outbox: OutboxPolicy(capacity: 12, historyLimit: 40, maxAttempts: 4),
            supervisor: SupervisorPolicy(heartbeatInterval: 1_000, deadAfter: 6_000,
                                         stalledAfter: 2_500, resyncAfterDegradedFor: 5_000,
                                         baseBackoff: 300, maxBackoff: 10_000,
                                         jitterFraction: 0.25, maxAttempts: 12),
            publish: PublishPolicy(byteThreshold: 1_024, maxLatency: 80))

        let chaos = Self.chaos(from: CommandLine.arguments)
        let server = ScriptedSessionServer(epoch: 1,
                                           events: SessionScript.turn(epoch: 1, parallelCalls: 3, textTokens: 34))
        // `pacing` makes the stream arrive at human speed rather than
        // instantly, so the transcript visibly streams on launch.
        let transport = ChaosTransport(server: server, policy: chaos, pacing: 45)
        self.model = SessionReplicaDemoModel(server: server,
                                             transport: transport,
                                             configuration: configuration,
                                             chaos: chaos)
    }

    /// Absent or unrecognised flag → a clean link. Never crashes on input.
    private static func chaos(from arguments: [String]) -> ChaosPolicy {
        guard let flagIndex = arguments.firstIndex(of: "-chaos"),
              arguments.indices.contains(flagIndex + 1) else { return .clean }
        switch arguments[flagIndex + 1].lowercased() {
        case "hostile": return .hostile
        case "drops": return ChaosPolicy(dropProbability: 0.25, seed: 11)
        case "duplicates": return ChaosPolicy(duplicateProbability: 0.4, seed: 12)
        case "reorder": return ChaosPolicy(reorderWindow: 6, seed: 13)
        case "stall": return ChaosPolicy(stallAfterFrames: 14, stallHeartbeats: 30, seed: 15)
        case "disconnect": return ChaosPolicy(disconnectAfterFrames: 20, seed: 14)
        default: return .clean
        }
    }

    var body: some Scene {
        WindowGroup {
            SessionReplicaDemoView(model: model)
        }
    }
}
