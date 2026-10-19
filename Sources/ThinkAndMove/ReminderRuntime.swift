import Foundation

enum ReminderInvitationKind: String, Equatable {
    case ai, usage, displayTest, scheduledBreak
}

struct ReminderPresentation: Equatable, Identifiable {
    let id: UUID
    let kind: ReminderInvitationKind
    let target: Int
    let shownAt: TimeInterval
    let expiresAt: TimeInterval
}

struct ReminderRuntimeContext {
    var isHome = false
    var settingsOpen = false
    var workoutActive = false
    var canRecord = false
    var isSystemActive = true
    var hasVerifiedProfile = false
    var inputQuietTime: TimeInterval?
    var keyboardQuietTime: TimeInterval?
    var target = 5
    /// Explicit display tests can be started from Settings or a result screen.
    var manualStartAllowed = false

    var automaticEligible: Bool {
        isHome && !settingsOpen && !workoutActive && canRecord && isSystemActive
    }
    var manualEligible: Bool {
        manualStartAllowed && !workoutActive && canRecord && isSystemActive
    }
}

/// Pure presentation/lifecycle state. It has no app, camera, AX, or timer APIs.
/// A successful accept returns a fixed target; later AI events only affect offers.
struct ReminderRuntime {
    let configuration: ReminderConfiguration
    let breakInterval: TimeInterval
    private var policy: ReminderPolicy
    private(set) var presentation: ReminderPresentation?
    private(set) var started = false
    private(set) var suspended = false
    private var aiEnabled = false
    private var breakEnabled = false
    private var nextBreakAt: TimeInterval?
    private var lastAutomaticShownAt: TimeInterval?
    private var lastTime: TimeInterval?

    init(configuration: ReminderConfiguration = ReminderConfiguration(), breakInterval: TimeInterval = 30 * 60) {
        self.configuration = configuration
        self.breakInterval = breakInterval
        policy = ReminderPolicy(configuration: configuration)
    }

    mutating func start(at now: TimeInterval, aiEnabled: Bool, breakEnabled: Bool) {
        guard now.isFinite else { return }
        started = true; suspended = false; lastTime = now
        self.aiEnabled = aiEnabled; self.breakEnabled = breakEnabled
        policy.setEnabled(aiEnabled)
        policy.selectSource(nil)
        presentation = nil
        nextBreakAt = breakEnabled ? now + breakInterval : nil
    }

    mutating func stop() {
        started = false; suspended = false; presentation = nil; nextBreakAt = nil
        policy.setEnabled(false); policy.suspend()
    }

    mutating func suspend() {
        suspended = true; presentation = nil; nextBreakAt = nil
        policy.suspend()
    }

    mutating func resume(at now: TimeInterval) {
        guard started, suspended, now.isFinite else { return }
        suspended = false; lastTime = now; presentation = nil
        policy.setEnabled(aiEnabled); policy.selectSource(nil)
        // Sleeping time never becomes a backlog of periodic invitations.
        nextBreakAt = breakEnabled ? now + breakInterval : nil
    }

    mutating func setAIEnabled(_ enabled: Bool) {
        aiEnabled = enabled
        policy.setEnabled(enabled)
        policy.selectSource(nil)
        if presentation?.kind == .ai { presentation = nil }
    }

    mutating func setBreakEnabled(_ enabled: Bool, at now: TimeInterval) {
        guard enabled != breakEnabled else { return }
        breakEnabled = enabled
        nextBreakAt = enabled && now.isFinite ? now + breakInterval : nil
        if !enabled, presentation?.kind == .scheduledBreak { presentation = nil }
    }

    mutating func selectSource(_ source: AIActivitySource?) {
        policy.selectSource(source)
        if presentation?.kind == .ai { presentation = nil }
    }

    mutating func receive(_ snapshot: AIActivitySnapshot) {
        guard started, !suspended else { return }
        _ = policy.receive(snapshot)
    }

    mutating func evaluate(at now: TimeInterval, context: ReminderRuntimeContext) {
        guard started, !suspended, advanceClock(to: now), context.isSystemActive else {
            presentation = nil
            return
        }
        if context.workoutActive, breakEnabled { nextBreakAt = now + breakInterval }
        if let current = presentation, now >= current.expiresAt { dismiss(id: current.id) }

        if let current = presentation, current.kind != .ai {
            let valid = current.kind == .displayTest ? context.manualEligible
                : breakEnabled && context.automaticEligible && isQuiet(context.keyboardQuietTime)
            if !valid { presentation = nil }
        }

        var aiContext = policyContext(context)
        // Another panel, or the common automatic cooldown, blocks new AI offers.
        // The cooldown must not invalidate the AI panel that started it.
        if presentation?.kind != .ai {
            aiContext.isEligible = aiContext.isEligible && presentation == nil && cooldownAllows(now)
        }
        switch policy.evaluate(at: now, context: aiContext) {
        case .present(let invitation):
            presentation = ReminderPresentation(id: invitation.id, kind: .ai, target: invitation.target,
                                                shownAt: invitation.shownAt, expiresAt: invitation.expiresAt)
            recordAutomaticPresentation(at: now)
        case .dismiss(let id):
            if presentation?.id == id { presentation = nil }
        case .none: break
        }

        guard presentation == nil, breakEnabled, context.automaticEligible,
              isQuiet(context.inputQuietTime), cooldownAllows(now),
              let due = nextBreakAt, now >= due else { return }
        presentation = makePresentation(kind: .scheduledBreak, at: now, target: context.target)
        recordAutomaticPresentation(at: now)
    }

    @discardableResult
    mutating func showTest(at now: TimeInterval, context: ReminderRuntimeContext) -> Bool {
        guard started, !suspended, advanceClock(to: now), context.manualEligible else { return false }
        if let current = presentation { dismiss(id: current.id) }
        presentation = makePresentation(kind: .displayTest, at: now, target: context.target)
        return true
    }

    mutating func accept(id: UUID, at now: TimeInterval, context: ReminderRuntimeContext) -> ReminderPresentation? {
        guard let current = presentation, current.id == id else { return nil }
        guard started, !suspended, advanceClock(to: now), now >= current.shownAt,
              now < current.expiresAt else { dismiss(id: id); return nil }
        switch current.kind {
        case .ai:
            var aiContext = policyContext(context)
            // Clicking this explicit button is itself an input event. Its own
            // click must not fail the idle-time test; all live safety gates,
            // generation, lease, and expiry are still rechecked by the policy.
            aiContext.inputQuietTime = configuration.minimumInputQuietTime
            guard policy.accept(id: id, at: now, context: aiContext) != nil else {
                presentation = nil; return nil
            }
        case .usage:
            guard context.automaticEligible else { presentation = nil; return nil }
        case .scheduledBreak:
            guard breakEnabled, context.automaticEligible else { presentation = nil; return nil }
        case .displayTest:
            guard context.manualEligible else { presentation = nil; return nil }
        }
        presentation = nil
        if breakEnabled { nextBreakAt = now + breakInterval }
        return current
    }

    mutating func dismiss(id: UUID) {
        guard presentation?.id == id else { return }
        policy.dismiss(id: id)
        presentation = nil
    }

    private mutating func advanceClock(to now: TimeInterval) -> Bool {
        guard now.isFinite, lastTime.map({ now >= $0 }) ?? true else {
            presentation = nil; policy.suspend()
            return false
        }
        lastTime = now
        return true
    }

    private func policyContext(_ context: ReminderRuntimeContext) -> ReminderContext {
        ReminderContext(isEligible: context.automaticEligible, isSystemActive: context.isSystemActive,
                        hasVerifiedProfile: context.hasVerifiedProfile,
                        inputQuietTime: presentation?.kind == .ai ? context.keyboardQuietTime : context.inputQuietTime,
                        target: context.target)
    }

    private func isQuiet(_ value: TimeInterval?) -> Bool {
        value.map { $0.isFinite && $0 >= configuration.minimumInputQuietTime } ?? false
    }

    private func cooldownAllows(_ now: TimeInterval) -> Bool {
        lastAutomaticShownAt.map { now >= $0 && now - $0 >= configuration.globalCooldown } ?? true
    }

    private mutating func recordAutomaticPresentation(at now: TimeInterval) {
        lastAutomaticShownAt = now
        if breakEnabled { nextBreakAt = now + breakInterval }
    }

    private func makePresentation(kind: ReminderInvitationKind, at now: TimeInterval, target: Int) -> ReminderPresentation {
        ReminderPresentation(id: UUID(), kind: kind, target: min(30, max(1, target)), shownAt: now,
                             expiresAt: now + configuration.invitationLifetime)
    }
}
