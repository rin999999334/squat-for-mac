import Foundation

/// Synthetic runtime and settings checks. No camera, AX process, or panel opens.
@main
struct ReminderControllerChecks {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label)
        passed += 1
    }

    @MainActor static func main() {
        let suite = "Squat.ReminderControllerChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        check(!settings.aiEnabled && !settings.breakRemindersEnabled, "Automatic invitations are opt-in")
        check(settings.aiProvider == .chatgptDesktop, "ChatGPT is the initial provider")
        settings.aiEnabled = true; settings.aiProvider = .claudeDesktop; settings.breakRemindersEnabled = true
        let restored = AppSettings(defaults: defaults)
        check(restored.aiEnabled && restored.aiProvider == .claudeDesktop && restored.breakRemindersEnabled, "Reminder preferences persist independently")
        defaults.set("invalid-provider", forKey: AppSettings.aiProviderKey)
        check(AppSettings(defaults: defaults).aiProvider == .chatgptDesktop, "Unknown saved provider falls back safely")

        var f = Fixture()
        f.send(.running, at: 9.9)
        check(f.current == nil, "A generation shorter than ten seconds does not invite")
        f.send(.running, at: 10)
        let ai = f.current!
        check(ai.kind == .ai && ai.target == 5, "A fresh long generation produces an AI invitation")
        check(ai.expiresAt == 18, "The invitation expires after eight seconds")
        f.context.inputQuietTime = 0
        f.tick(10.2)
        check(f.current?.id == ai.id, "Moving the mouse or clicking elsewhere does not dismiss an offered panel")
        f.context.keyboardQuietTime = 0
        f.tick(10.3)
        check(f.current == nil, "Resuming keyboard input withdraws the offered panel")
        f.context.inputQuietTime = 10; f.context.keyboardQuietTime = 10
        f.send(.running, at: 11)
        check(f.current == nil, "A withdrawn generation is not offered again")

        f = Fixture()
        f.context.inputQuietTime = 2
        f.send(.running, at: 10)
        check(f.current == nil, "Recent clicks or scrolling postpone a new offer")
        f.context.inputQuietTime = nil
        f.send(.running, at: 10.5)
        check(f.current == nil, "Unavailable aggregate input time suppresses automatic offers")
        f.context.inputQuietTime = 3
        f.send(.running, at: 11)
        check(f.current?.kind == .ai, "Three quiet seconds permit a new offer")

        f = Fixture()
        f.context.target = 9
        f.send(.running, at: 10)
        let offered = f.current!
        f.context.target = 22
        f.context.inputQuietTime = 0; f.context.keyboardQuietTime = 0
        check(f.click(offered.id, at: 10.2), "The explicit Start click does not reject its own input")
        check(f.startedTargets == [9] && f.current == nil, "Start uses the offered target rather than a changed preference")
        f.send(.idle, at: 10.4)
        check(f.context.workoutActive && f.startedTargets == [9], "AI completion after accepted Start leaves the workout running")
        check(!f.click(offered.id, at: 10.5) && f.startedTargets.count == 1, "A repeated Start cannot create another workout")

        for phase in [AIPhase.idle, .unknown, .awaitingUser, .unavailable] {
            f = Fixture(); f.send(.running, at: 10)
            let id = f.current!.id
            f.send(phase, at: 10.2)
            check(f.current == nil && !f.click(id, at: 10.3), "\(phase) immediately withdraws the AI offer")
        }
        f = Fixture(); f.send(.running, at: 10)
        let expiredLease = f.current!.id
        check(!f.click(expiredLease, at: 12.01), "Start rechecks the two-second generation lease")
        f = Fixture(); f.send(.running, at: 10)
        let expiredOffer = f.current!.id
        f.send(.running, at: 18)
        check(f.current == nil && !f.click(expiredOffer, at: 18), "Expired panels cannot start a workout")
        f = Fixture(); f.send(.running, at: 10)
        let revoked = f.current!.id
        f.context.hasVerifiedProfile = false
        check(!f.click(revoked, at: 10.1), "Permission loss or setup state is rechecked at Start")

        for reason in 0..<5 {
            f = Fixture(); f.send(.running, at: 10)
            switch reason {
            case 0: f.context.isHome = false
            case 1: f.context.settingsOpen = true
            case 2: f.context.workoutActive = true
            case 3: f.context.canRecord = false
            default: f.context.hasVerifiedProfile = false
            }
            f.tick(10.1)
            check(f.current == nil, "A changed screen/settings/workout/storage/profile gate closes the AI offer (\(reason))")
        }

        f = Fixture(); f.send(.running, at: 10)
        f.runtime.selectSource(nil); f.tick(10.1)
        check(f.current == nil, "Changing the monitored source closes its prior offer")
        f.send(.running, at: 10.2)
        check(f.current == nil, "A retired source cannot revive an offer")
        f = Fixture(); f.send(.running, at: 10)
        f.runtime.setAIEnabled(false); f.tick(10.1)
        check(f.current == nil, "Turning off automatic AI invitations closes the panel")

        f = Fixture(aiEnabled: false)
        f.context.settingsOpen = true; f.context.inputQuietTime = 0
        check(f.runtime.showTest(at: 0, context: f.context), "A user can explicitly request a display test from Settings")
        let test = f.current!
        check(test.kind == .displayTest, "A display test has a distinct type and does not claim AI detection")
        f.context.settingsOpen = false
        check(f.click(test.id, at: 0.2) && f.startedTargets == [5], "A display test starts only after its explicit button click")
        f = Fixture(aiEnabled: false)
        f.context.workoutActive = true
        check(!f.runtime.showTest(at: 0, context: f.context), "A display test cannot interrupt an active workout")
        f = Fixture(aiEnabled: false)
        f.context.canRecord = false
        check(!f.runtime.showTest(at: 0, context: f.context), "A display test cannot bypass a storage failure")

        f = Fixture(aiEnabled: false, breakEnabled: true, breakInterval: 30)
        f.tick(29.9)
        check(f.current == nil, "Periodic reminders do not arrive before their interval")
        f.context.inputQuietTime = 0
        f.tick(30)
        check(f.current == nil, "Input activity postpones a due periodic reminder")
        f.context.inputQuietTime = 3
        f.tick(31)
        let periodic = f.current!
        check(periodic.kind == .scheduledBreak, "A due quiet period produces a distinct break invitation")
        f.context.inputQuietTime = 0; f.tick(31.2)
        check(f.current?.id == periodic.id, "Moving toward the break panel does not dismiss it")
        f.context.keyboardQuietTime = 0; f.tick(31.3)
        check(f.current == nil, "Keyboard input also withdraws a break panel")
        f.context.keyboardQuietTime = 10; f.context.inputQuietTime = 10
        f.tick(100)
        check(f.current == nil, "An ignored break does not repeat within the common cooldown")

        f = Fixture(breakEnabled: true, breakInterval: 30)
        f.send(.running, at: 10)
        f.runtime.dismiss(id: f.current!.id)
        f.send(.idle, at: 11)
        f.tick(40)
        check(f.current == nil, "An AI invitation also starts the break reminder cooldown")
        f.tick(910)
        check(f.current?.kind == .scheduledBreak, "A postponed break can appear after the common fifteen-minute cooldown")

        f = Fixture(breakEnabled: true, breakInterval: 30)
        f.tick(30)
        f.runtime.dismiss(id: f.current!.id)
        f.send(.running, at: 40, startedAt: 30)
        check(f.current == nil, "A break invitation also starts the AI reminder cooldown")
        f.generation = UUID()
        f.send(.running, at: 930, startedAt: 920)
        check(f.current?.kind == .ai, "A fresh AI generation can invite after the shared cooldown")

        f = Fixture(aiEnabled: false, breakEnabled: true, breakInterval: 30)
        f.context.workoutActive = true; f.tick(30)
        check(f.current == nil, "No periodic invitation appears during a workout")
        f.context.workoutActive = false; f.tick(59.9)
        check(f.current == nil, "The completed workout postpones the next periodic reminder")
        f.tick(60)
        check(f.current?.kind == .scheduledBreak, "A new full quiet interval can produce the next break")

        f = Fixture(breakEnabled: true, breakInterval: 30)
        f.send(.running, at: 10)
        f.runtime.suspend()
        check(f.current == nil, "Lock or sleep immediately removes the panel")
        f.runtime.resume(at: 1_000)
        f.send(.running, at: 1_000, startedAt: 990)
        check(f.current == nil, "Waking discards both the old source and accumulated break time")
        f.tick(1_029.9)
        check(f.current == nil, "A full break interval starts again after waking")
        f.runtime.resume(at: 1_029.9)
        f.tick(1_030)
        check(f.current?.kind == .scheduledBreak, "A duplicate wake event does not restart the interval or create a backlog")

        f = Fixture(); f.send(.running, at: 10)
        f.tick(9)
        check(f.current == nil, "A backward monotonic clock clears an offer")
        f.send(.running, at: 11)
        check(f.current == nil, "Clock rollback also invalidates the selected AI epoch")
        f = Fixture(); f.send(.running, at: 10)
        f.runtime.stop(); f.tick(11)
        check(f.current == nil, "Stopping the controller removes all invitations")
        f.runtime.start(at: 20, aiEnabled: true, breakEnabled: false)
        f.runtime.selectSource(f.source); f.generation = UUID()
        f.send(.running, at: 30, startedAt: 20)
        check(f.current == nil, "Stopping and restarting the same controller preserves the automatic cooldown")
        f.generation = UUID(); f.send(.running, at: 910, startedAt: 900)
        check(f.current?.kind == .ai, "The retained cooldown eventually permits a fresh generation")
        let oldID = f.current!.id
        _ = f.runtime.showTest(at: 910.1, context: f.context)
        let replacement = f.current!.id
        check(!f.click(oldID, at: 910.2) && f.current?.id == replacement, "A stale panel callback cannot replace or dismiss a newer test panel")
        f = Fixture(aiEnabled: false)
        f.context.target = 99
        _ = f.runtime.showTest(at: 0, context: f.context)
        check(f.current?.target == 30, "Explicit invitations clamp invalid goals")
        print("PASS: \(passed) reminder runtime/settings checks (synthetic; no AI or camera opened)")
    }

    struct Fixture {
        var runtime: ReminderRuntime
        var context = ReminderRuntimeContext()
        let source = AIActivitySource(provider: .chatgptDesktop, processID: 1, sourceID: UUID())
        var generation = UUID()
        var sequence: UInt64 = 0
        var startedTargets: [Int] = []
        var current: ReminderPresentation? { runtime.presentation }

        init(aiEnabled: Bool = true, breakEnabled: Bool = false, breakInterval: TimeInterval = 1_800) {
            runtime = ReminderRuntime(breakInterval: breakInterval)
            context.isHome = true; context.canRecord = true; context.hasVerifiedProfile = true
            context.inputQuietTime = 10; context.keyboardQuietTime = 10; context.manualStartAllowed = true
            runtime.start(at: 0, aiEnabled: aiEnabled, breakEnabled: breakEnabled)
            runtime.selectSource(source)
        }

        mutating func tick(_ time: TimeInterval) { runtime.evaluate(at: time, context: context) }

        mutating func send(_ phase: AIPhase, at time: TimeInterval, startedAt: TimeInterval = 0) {
            sequence += 1
            runtime.receive(AIActivitySnapshot(provider: source.provider, processID: source.processID,
                                               sourceID: source.sourceID, generationID: generation,
                                               phase: phase, observedAt: time, sequence: sequence,
                                               runningSince: startedAt))
            tick(time)
        }

        mutating func click(_ id: UUID, at time: TimeInterval) -> Bool {
            guard let accepted = runtime.accept(id: id, at: time, context: context) else { return false }
            // A fake app boundary; it records the accepted target without Camera.
            startedTargets.append(accepted.target)
            context.workoutActive = true; context.isHome = false
            return true
        }
    }
}
