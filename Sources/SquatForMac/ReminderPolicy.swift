import Foundation

struct ReminderConfiguration {
    var waitThreshold: TimeInterval = 10
    var minimumInputQuietTime: TimeInterval = 3
    var maximumCandidateAge: TimeInterval = 120
    var invitationLifetime: TimeInterval = 8
    var globalCooldown: TimeInterval = 15 * 60
    var runningLease: TimeInterval = 2
}

struct ReminderContext {
    /// Home only: false during welcome, settings, preparation, workout, or results.
    var isEligible = false
    var isSystemActive = true
    var hasVerifiedProfile = false
    var inputQuietTime: TimeInterval?
    var target = 5
}

struct ReminderInvitation: Equatable, Identifiable {
    let id: UUID
    let provider: AIProvider
    let sourceID: UUID
    let generationID: UUID
    let target: Int
    let shownAt: TimeInterval
    let expiresAt: TimeInterval
}

enum ReminderDecision: Equatable {
    case none
    case present(ReminderInvitation)
    case dismiss(UUID)
}

/// Scheduling only. It never reads another app or starts a camera.
struct ReminderPolicy {
    let configuration: ReminderConfiguration
    private(set) var enabled = false
    private(set) var invitation: ReminderInvitation?
    private(set) var selectedSource: AIActivitySource?
    private(set) var latestSnapshot: AIActivitySnapshot?
    private var lastShownAt: TimeInterval?
    private var lastEvaluationAt: TimeInterval?
    private var consumedGenerations = Set<GenerationKey>()
    private var inferredStarts: [GenerationKey: TimeInterval] = [:]

    private struct GenerationKey: Hashable {
        let provider: AIProvider
        let sourceID: UUID
        let generationID: UUID
    }

    init(configuration: ReminderConfiguration = ReminderConfiguration()) {
        self.configuration = configuration
    }

    mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        latestSnapshot = nil
        invitation = nil
        // Cooldown and consumed generations intentionally survive toggling.
    }

    mutating func selectSource(_ source: AIActivitySource?) {
        selectedSource = source
        latestSnapshot = nil
        invitation = nil
    }

    @discardableResult
    mutating func receive(_ snapshot: AIActivitySnapshot) -> Bool {
        guard snapshot.source == selectedSource,
              snapshot.observedAt.isFinite,
              latestSnapshot.map({ snapshot.sequence > $0.sequence && snapshot.observedAt >= $0.observedAt }) ?? true else {
            return false
        }
        if let startedAt = snapshot.runningSince,
           (!startedAt.isFinite || startedAt > snapshot.observedAt) { return false }
        latestSnapshot = snapshot
        if let key = generationKey(snapshot), inferredStarts[key] == nil {
            inferredStarts[key] = snapshot.runningSince ?? snapshot.observedAt
        }
        return true
    }

    mutating func evaluate(at now: TimeInterval, context: ReminderContext) -> ReminderDecision {
        guard now.isFinite, lastEvaluationAt.map({ now >= $0 }) ?? true else {
            latestSnapshot = nil
            return dismissCurrent()
        }
        lastEvaluationAt = now
        guard let snapshot = eligibleSnapshot(at: now, context: context),
              let key = generationKey(snapshot), let startedAt = inferredStarts[key] else {
            return dismissCurrent()
        }
        let age = now - startedAt
        guard age >= 0, age <= configuration.maximumCandidateAge else {
            consumedGenerations.insert(key)
            return dismissCurrent()
        }
        if let current = invitation {
            guard current.sourceID == snapshot.sourceID,
                  current.generationID == snapshot.generationID,
                  now < current.expiresAt else { return dismissCurrent() }
            return .none
        }
        guard age >= configuration.waitThreshold,
              !consumedGenerations.contains(key),
              lastShownAt.map({ now >= $0 && now - $0 >= configuration.globalCooldown }) ?? true else { return .none }
        let proposed = ReminderInvitation(id: UUID(), provider: snapshot.provider,
                                          sourceID: snapshot.sourceID, generationID: key.generationID,
                                          target: min(30, max(1, context.target)), shownAt: now,
                                          expiresAt: now + configuration.invitationLifetime)
        invitation = proposed
        consumedGenerations.insert(key)
        lastShownAt = now
        return .present(proposed)
    }

    /// A stale panel can never start a workout. On success the caller starts an
    /// independent session; subsequent AI state changes cannot cancel that session.
    mutating func accept(id: UUID, at now: TimeInterval, context: ReminderContext) -> ReminderInvitation? {
        guard let current = invitation, current.id == id else { return nil }
        guard now.isFinite,
              lastEvaluationAt.map({ now >= $0 }) ?? true,
              now >= current.shownAt, now < current.expiresAt,
              let snapshot = eligibleSnapshot(at: now, context: context),
              snapshot.sourceID == current.sourceID,
              snapshot.generationID == current.generationID,
              let key = generationKey(snapshot), let startedAt = inferredStarts[key],
              now - startedAt <= configuration.maximumCandidateAge else {
            invitation = nil
            return nil
        }
        invitation = nil
        return current
    }

    mutating func dismiss(id: UUID) {
        if invitation?.id == id { invitation = nil }
    }

    /// Sleep, lock, permission loss, or monitor restart discards the current epoch.
    /// Keep the global cooldown so waking cannot immediately repeat an invitation.
    mutating func suspend() {
        selectedSource = nil
        latestSnapshot = nil
        invitation = nil
    }

    private func eligibleSnapshot(at now: TimeInterval, context: ReminderContext) -> AIActivitySnapshot? {
        guard enabled, context.isEligible, context.isSystemActive, context.hasVerifiedProfile,
              let quiet = context.inputQuietTime, quiet.isFinite,
              quiet >= configuration.minimumInputQuietTime,
              let snapshot = latestSnapshot, snapshot.phase == .running,
              snapshot.generationID != nil,
              now >= snapshot.observedAt,
              now - snapshot.observedAt <= configuration.runningLease else { return nil }
        return snapshot
    }

    private func generationKey(_ snapshot: AIActivitySnapshot) -> GenerationKey? {
        guard let generationID = snapshot.generationID else { return nil }
        return GenerationKey(provider: snapshot.provider, sourceID: snapshot.sourceID, generationID: generationID)
    }

    private mutating func dismissCurrent() -> ReminderDecision {
        guard let current = invitation else { return .none }
        invitation = nil
        return .dismiss(current.id)
    }
}
