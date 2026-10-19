import Foundation

@main
struct AIActivityChecks {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        passed += 1
    }

    static func main() {
        let source = AIActivitySource(provider: .chatgptDesktop, processID: 10, sourceID: UUID())
        var tracker = AIActivityTracker()
        tracker.selectSource(source)
        check(tracker.observe(source: source, phase: .running, at: 0, sequence: 1)?.phase == .unknown, "AI11 launch during generation stays unknown")
        check(tracker.observe(source: source, phase: .running, at: 0.5, sequence: 2)?.generationID == nil, "AI11 running without idle never creates generation")
        _ = tracker.observe(source: source, phase: .idle, at: 1, sequence: 3)
        check(tracker.observe(source: source, phase: .running, at: 2, sequence: 4)?.phase == .unknown, "first positive remains unknown")
        let confirmed = tracker.observe(source: source, phase: .running, at: 2.5, sequence: 5)!
        check(confirmed.phase == .running && confirmed.generationID != nil, "second positive confirms generation")
        check(confirmed.runningSince == 2, "wait begins at first positive")
        let generation = confirmed.generationID
        check(tracker.observe(source: source, phase: .unknown, at: 3, sequence: 6)?.phase == .unknown, "unknown suppresses immediately")
        _ = tracker.observe(source: source, phase: .running, at: 3.5, sequence: 7)
        let resumed = tracker.observe(source: source, phase: .running, at: 4, sequence: 8)!
        check(resumed.generationID == generation && resumed.runningSince == 2, "reacquisition retains generation")
        check(tracker.observe(source: source, phase: .idle, at: 4, sequence: 7) == nil, "AI10 sequence inversion ignored")
        check(tracker.observe(source: source, phase: .idle, at: 3, sequence: 9) == nil, "time inversion ignored")
        let other = AIActivitySource(provider: .claudeDesktop, processID: 20, sourceID: UUID())
        tracker.selectSource(other)
        check(tracker.observe(source: source, phase: .running, at: 5, sequence: 9) == nil, "AI10 retired epoch ignored")
        _ = tracker.observe(source: other, phase: .idle, at: 5, sequence: 1)
        _ = tracker.observe(source: other, phase: .running, at: 6, sequence: 2)
        let next = tracker.observe(source: other, phase: .running, at: 6.5, sequence: 3)!
        check(next.generationID != generation, "new epoch creates distinct generation")
        _ = tracker.observe(source: other, phase: .awaitingUser, at: 7, sequence: 4)
        check(tracker.observe(source: other, phase: .running, at: 7.5, sequence: 5)?.phase == .unknown, "awaiting user requires new idle")

        var f = Fixture()
        f.send(.running, at: 8)
        check(f.policy.evaluate(at: 8, context: f.context) == .none, "AI01 short response does not invite")
        f.send(.idle, at: 9)
        check(f.policy.evaluate(at: 10, context: f.context) == .none, "AI01 completed short response stays silent")
        f = Fixture()
        let invitation = f.present()
        check(invitation?.target == 5, "AI02 long fresh generation invites once")
        f.send(.running, at: 11)
        check(f.policy.evaluate(at: 11, context: f.context) == .none, "AI03 current invitation not repeated")
        f.send(.running, at: 18)
        check(f.policy.evaluate(at: 18, context: f.context) == .dismiss(invitation!.id), "AI04 lifetime is eight seconds")
        f.send(.running, at: 60)
        check(f.policy.evaluate(at: 60, context: f.context) == .none, "AI03 generation consumed after expiry")
        f.send(.running, at: 911)
        check(f.policy.evaluate(at: 911, context: f.context) == .none, "same generation never repeats after cooldown")

        f = Fixture()
        let stopping = f.present()!
        f.send(.idle, at: 10.5)
        check(f.policy.evaluate(at: 10.5, context: f.context) == .dismiss(stopping.id), "AI05 completion withdraws invitation")
        check(f.policy.accept(id: stopping.id, at: 10.5, context: f.context) == nil, "AI16 withdrawn invitation cannot start")
        f = Fixture()
        let accepted = f.present()!
        check(f.policy.accept(id: accepted.id, at: 10.5, context: f.context)?.target == 5, "AI06 fresh click accepted")
        f.send(.idle, at: 11)
        check(f.policy.evaluate(at: 11, context: f.context) == .none, "AI06 accepted workout has no dismissal callback")
        f.policy.selectSource(other)
        f.send(.running, at: 30, source: other, generation: UUID(), startedAt: 20)
        check(f.policy.evaluate(at: 30, context: f.context) == .none, "AI07 cooldown spans providers")

        for phase in [AIPhase.unknown, .awaitingUser, .unavailable] {
            f = Fixture()
            f.send(phase, at: 10)
            check(f.policy.evaluate(at: 10, context: f.context) == .none, "AI08 \(phase) suppresses invitation")
        }
        f = Fixture()
        f.send(.running, at: 7)
        check(f.policy.evaluate(at: 10, context: f.context) == .none, "AI08 stale lease suppresses invitation")
        f = Fixture()
        let lease = f.present()!
        check(f.policy.accept(id: lease.id, at: 12.01, context: f.context) == nil, "AI16 stale lease at click cannot start")
        f = Fixture()
        f.context.isEligible = false
        check(f.present() == nil, "AI09 non-home screens suppress invitation")
        f = Fixture()
        f.send(.running, at: 10)
        let delayed = AIActivitySnapshot(provider: f.source.provider, processID: f.source.processID,
                                        sourceID: UUID(), generationID: f.generation,
                                        phase: .running, observedAt: 11, sequence: 99, runningSince: 0)
        check(!f.policy.receive(delayed), "AI10 different source rejected")
        let repeated = AIActivitySnapshot(provider: f.source.provider, processID: f.source.processID,
                                         sourceID: f.source.sourceID, generationID: f.generation,
                                         phase: .idle, observedAt: 11, sequence: f.sequence)
        check(!f.policy.receive(repeated), "AI10 duplicate sequence rejected")
        f = Fixture()
        let sleeping = f.present()!
        f.context.isSystemActive = false
        check(f.policy.evaluate(at: 10.5, context: f.context) == .dismiss(sleeping.id), "AI12 inactive system withdraws invitation")
        f.policy.suspend()
        f.context.isSystemActive = true
        check(f.policy.evaluate(at: 11, context: f.context) == .none, "AI12 resume does not revive snapshot")
        f = Fixture()
        let reversed = f.present()!
        check(f.policy.evaluate(at: 9, context: f.context) == .dismiss(reversed.id), "AI12 reversed monotonic clock invalidates snapshot")
        f = Fixture()
        f.context.inputQuietTime = 1
        check(f.present() == nil, "AI13 recent input suppresses invitation")
        f.send(.running, at: 121)
        f.context.inputQuietTime = 4
        check(f.policy.evaluate(at: 121, context: f.context) == .none, "AI13 candidate older than 120 seconds skipped")
        f = Fixture()
        f.context.inputQuietTime = nil
        check(f.present() == nil, "AI14 unknown input quiet time suppresses invitation")
        f = Fixture()
        f.context.hasVerifiedProfile = false
        check(f.present() == nil, "AI14 unverified provider suppresses invitation")
        f = Fixture()
        f.policy.setEnabled(false)
        check(f.present() == nil, "AI14 disabled monitoring suppresses invitation")
        f = Fixture()
        let switched = f.present()!
        f.policy.selectSource(other)
        check(f.policy.invitation == nil, "AI15 source switch withdraws old invitation")
        check(f.policy.accept(id: switched.id, at: 10.5, context: f.context) == nil, "AI16 delayed old panel callback rejected")
        f = Fixture()
        f.context.target = 9
        let nine = f.present()!
        f.context.target = 20
        check(f.policy.accept(id: nine.id, at: 10.5, context: f.context)?.target == 9, "invitation target is a snapshot")
        f = Fixture()
        let expired = f.present()!
        f.send(.running, at: 18)
        check(f.policy.accept(id: expired.id, at: 18, context: f.context) == nil, "AI16 expired panel cannot start")
        f = Fixture()
        let current = f.present()!
        check(f.policy.accept(id: UUID(), at: 10.5, context: f.context) == nil && f.policy.invitation?.id == current.id, "old panel callback cannot dismiss a different current panel")
        f = Fixture()
        f.send(.running, at: 119)
        let late: ReminderInvitation
        if case .present(let invitation) = f.policy.evaluate(at: 119, context: f.context) { late = invitation }
        else { fatalError("Expected late candidate") }
        f.send(.running, at: 121)
        check(f.policy.accept(id: late.id, at: 121, context: f.context) == nil, "candidate maximum age also checked at Start")
        f = Fixture()
        let forward = f.present()!
        f.send(.running, at: 11)
        _ = f.policy.evaluate(at: 11, context: f.context)
        check(f.policy.accept(id: forward.id, at: 10.5, context: f.context) == nil, "Start rejects a reversed monotonic clock")
        print("AI activity and reminder checks passed: \(passed)")
    }
}

private struct Fixture {
    var source = AIActivitySource(provider: .chatgptDesktop, processID: 10, sourceID: UUID())
    var generation = UUID()
    var sequence: UInt64 = 0
    var policy = ReminderPolicy()
    var context = ReminderContext(isEligible: true, isSystemActive: true, hasVerifiedProfile: true, inputQuietTime: 4, target: 5)
    init() {
        policy.setEnabled(true)
        policy.selectSource(source)
    }
    mutating func send(_ phase: AIPhase, at time: TimeInterval, source: AIActivitySource? = nil,
                       generation: UUID? = nil, startedAt: TimeInterval = 0) {
        sequence += 1
        let actual = source ?? self.source
        _ = policy.receive(AIActivitySnapshot(provider: actual.provider, processID: actual.processID,
                                             sourceID: actual.sourceID,
                                             generationID: phase == .running ? (generation ?? self.generation) : nil,
                                             phase: phase, observedAt: time, sequence: sequence,
                                             runningSince: phase == .running ? startedAt : nil))
    }
    mutating func present() -> ReminderInvitation? {
        send(.running, at: 10)
        if case .present(let invitation) = policy.evaluate(at: 10, context: context) { return invitation }
        return nil
    }
}
