import Foundation

/// Local state only. No prompt, response, window title, or conversation identifier.
enum AIProvider: String, CaseIterable, Codable {
    case chatgptDesktop
    case claudeDesktop
}

enum AIPhase: String, Codable {
    case idle, running, awaitingUser, unknown, unavailable
}

struct AIActivitySource: Equatable {
    let provider: AIProvider
    let processID: Int32
    let sourceID: UUID
}

struct AIActivitySnapshot: Equatable {
    let provider: AIProvider
    let processID: Int32
    let sourceID: UUID
    let generationID: UUID?
    let phase: AIPhase
    let observedAt: TimeInterval
    let sequence: UInt64
    /// The first positive observation, using the same monotonic clock as observedAt.
    let runningSince: TimeInterval?

    init(provider: AIProvider, processID: Int32, sourceID: UUID,
         generationID: UUID?, phase: AIPhase, observedAt: TimeInterval,
         sequence: UInt64, runningSince: TimeInterval? = nil) {
        self.provider = provider
        self.processID = processID
        self.sourceID = sourceID
        self.generationID = generationID
        self.phase = phase
        self.observedAt = observedAt
        self.sequence = sequence
        self.runningSince = runningSince
    }

    var source: AIActivitySource {
        AIActivitySource(provider: provider, processID: processID, sourceID: sourceID)
    }
}

/// Turns verified control observations into a conservative generation state.
/// Selecting an epoch is explicit, so a late callback cannot revive an old window.
struct AIActivityTracker {
    private(set) var source: AIActivitySource?
    private var lastSequence: UInt64?
    private var lastObservedAt: TimeInterval?
    private var hasObservedIdle = false
    private var positiveCount = 0
    private var firstPositiveAt: TimeInterval?
    private var generationID: UUID?
    private var generationStartedAt: TimeInterval?

    mutating func selectSource(_ source: AIActivitySource?) {
        self = AIActivityTracker()
        self.source = source
    }

    mutating func observe(source: AIActivitySource, phase: AIPhase,
                          at time: TimeInterval, sequence: UInt64) -> AIActivitySnapshot? {
        guard self.source == source, time.isFinite,
              lastSequence.map({ sequence > $0 }) ?? true,
              lastObservedAt.map({ time >= $0 }) ?? true else { return nil }
        lastSequence = sequence
        lastObservedAt = time
        var confirmedPhase = phase

        switch phase {
        case .idle:
            hasObservedIdle = true
            positiveCount = 0
            firstPositiveAt = nil
            generationID = nil
            generationStartedAt = nil
        case .running:
            guard hasObservedIdle else {
                return snapshot(source: source, phase: .unknown, time: time, sequence: sequence)
            }
            if positiveCount == 0 { firstPositiveAt = time }
            positiveCount += 1
            if positiveCount < 2 {
                confirmedPhase = .unknown
            } else if generationID == nil {
                generationID = UUID()
                generationStartedAt = firstPositiveAt
            }
        case .unknown:
            // Suppress immediately. Retain an existing generation to prevent a
            // second invitation when the same generation becomes readable again.
            positiveCount = 0
            firstPositiveAt = nil
        case .awaitingUser, .unavailable:
            hasObservedIdle = false
            positiveCount = 0
            firstPositiveAt = nil
            generationID = nil
            generationStartedAt = nil
        }
        return snapshot(source: source, phase: confirmedPhase, time: time, sequence: sequence)
    }

    private func snapshot(source: AIActivitySource, phase: AIPhase,
                          time: TimeInterval, sequence: UInt64) -> AIActivitySnapshot {
        AIActivitySnapshot(provider: source.provider, processID: source.processID,
                           sourceID: source.sourceID, generationID: generationID,
                           phase: phase, observedAt: time, sequence: sequence,
                           runningSince: generationStartedAt)
    }
}
