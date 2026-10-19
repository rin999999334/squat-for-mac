import Foundation

@main struct UsageReminderChecks {
    static func main() throws {
        var checked = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checked += 1 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10))!
        func sample(_ time: Double, front: Bool = true, active: Bool = true, idle: Double? = 0) -> UsageObservation {
            UsageObservation(time: time, date: date.addingTimeInterval(time), targetIsFront: front, systemActive: active, idleSeconds: idle)
        }
        func tracker() -> UsageTimeTracker { UsageTimeTracker(provider: "chatgptDesktop", date: date, calendar: calendar) }
        var t = tracker()
        for second in 0..<3600 { t.observe(sample(Double(second))) }
        check(t.aggregate.seconds == 3599, "59:59 does not complete an hour")
        t.observe(sample(3600)); check(t.aggregate.seconds == 3600, "60:00 reaches the threshold")
        t = tracker()
        for second in 0...1800 { t.observe(sample(Double(second))) }
        for second in 1801...3000 { t.observe(sample(Double(second), front: false)) }
        for second in 3001...4802 { t.observe(sample(Double(second))) }
        check(t.aggregate.seconds == 3600, "Target usage accumulates across an unrelated app without counting its time")
        t = tracker()
        for second in 0...3600 { t.observe(sample(Double(second), idle: Double(second))) }
        check(t.aggregate.seconds == 300, "An hour of no input contributes at most the five-minute reading allowance")
        t = tracker(); t.observe(sample(0)); t.observe(sample(1000))
        check(t.aggregate.seconds == 0, "Unknown long intervals do not become usage")
        t.observe(sample(1001)); check(t.aggregate.seconds == 1, "Sampling resumes after a long interval")
        t.observe(sample(1000)); check(t.aggregate.seconds == 1, "Clock reversal never subtracts or adds time")
        t = tracker(); t.observe(sample(0)); t.observe(sample(1, idle: nil)); t.observe(sample(2, active: false))
        check(t.aggregate.seconds == 0, "Unknown idle and suspended state do not count")
        t = tracker(); for second in 0...60 { t.observe(sample(Double(second))) }
        let saved = try JSONDecoder().decode(UsageAggregate.self, from: JSONEncoder().encode(t.aggregate))
        var restored = UsageTimeTracker(provider: "chatgptDesktop", date: date.addingTimeInterval(1000), saved: saved, calendar: calendar)
        restored.observe(sample(2000)); check(restored.aggregate.seconds == 60, "Restart restores aggregate, not time spent while quit")
        check(UsageTimeTracker(provider: "claudeDesktop", date: date, saved: saved, calendar: calendar).aggregate.seconds == 0, "Provider change discards accumulated target time")
        restored.observe(UsageObservation(time: 2001, date: date.addingTimeInterval(86400), targetIsFront: true, systemActive: true, idleSeconds: 0))
        check(restored.aggregate.seconds == 0, "Local day change resets accumulation")
        restored.pauseToday(at: date.addingTimeInterval(86400)); check(restored.paused, "Pause applies to the current local day")
        var config = UsageReminderConfiguration(); config.threshold = 10; config.minimumNoticeInterval = 10
        var p = UsageReminderPolicy(tracker: UsageTimeTracker(provider: "chatgptDesktop", date: date, configuration: config, calendar: calendar))
        var context = UsageReminderContext(enabled: true, eligible: true, targetIsFront: true, inputQuietTime: 0, target: 9)
        for second in 0...10 { p.receive(sample(Double(second)), context: context) }
        check(p.presentation == nil && p.aggregate.seconds == 10, "Typing holds the proposal at its threshold")
        context.inputQuietTime = 3; p.evaluate(time: 11, date: date.addingTimeInterval(11), context: context)
        let invitation = p.presentation!
        check(invitation.kind == .usage && invitation.target == 9, "A quiet moment presents a usage card with the captured goal")
        check(p.aggregate.seconds == 0 && p.aggregate.lastNotice == date.addingTimeInterval(11), "Display consumes accumulated time and records cooldown")
        context.target = 3
        check(p.accept(id: UUID(), time: 12, context: context) == nil && p.presentation != nil, "An unrelated click cannot accept or dismiss the card")
        check(p.accept(id: invitation.id, time: 12, context: context)?.target == 9, "Acceptance retains the displayed goal")
        check(p.accept(id: invitation.id, time: 12, context: context) == nil, "Acceptance cannot be replayed")
        for second in 12...21 { p.receive(sample(Double(second)), context: context) }
        check(p.presentation != nil, "A new full usage interval can propose another break")
        let expired = p.presentation!; p.evaluate(time: expired.expiresAt, date: date.addingTimeInterval(expired.expiresAt), context: context)
        check(p.presentation == nil && p.accept(id: expired.id, time: expired.expiresAt, context: context) == nil, "Expired cards and late clicks are rejected")
        p.resetForWorkout(); check(p.aggregate.seconds == 0 && p.presentation == nil, "A completed real workout clears accumulated time and proposals")
        p.pauseToday(at: date); check(p.paused, "Policy exposes today's pause")
        p.receive(sample(30), context: context); check(p.presentation == nil && p.aggregate.seconds == 0, "Pause prevents invitations and counting")
        p = UsageReminderPolicy(tracker: UsageTimeTracker(provider: "chatgptDesktop", date: date, configuration: config, calendar: calendar))
        context.eligible = false
        for second in 0...10 { p.receive(sample(Double(second)), context: context) }
        p.evaluate(time: 310, date: date.addingTimeInterval(310), context: context)
        check(p.aggregate.seconds == 0 && p.nextDeadline == nil, "Undisplayable candidates expire without a backlog")
        context.eligible = true
        for second in 311...322 { p.receive(sample(Double(second)), context: context) }
        check(p.presentation != nil, "Fresh usage can create a candidate after an expired one")
        context.targetIsFront = false; p.evaluate(time: 323, date: date.addingTimeInterval(323), context: context)
        check(p.presentation == nil, "Leaving the target hides an existing card")
        var pending = saved; pending.seconds = 3600
        check(UsageTimeTracker(provider: "chatgptDesktop", date: date, saved: pending, calendar: calendar).aggregate.seconds == 0, "Restart discards a previously pending proposal instead of replaying it")
        context = UsageReminderContext(enabled: true, eligible: true, targetIsFront: true, inputQuietTime: 3, target: 5)
        for interval in UsageReminderInterval.allCases {
            let configuration = UsageReminderConfiguration(interval: interval)
            check(configuration.threshold == Double(interval.rawValue * 60) && configuration.minimumNoticeInterval == configuration.threshold,
                  "Selected interval controls both accumulation and minimum notice interval")
            p = UsageReminderPolicy(tracker: UsageTimeTracker(provider: "chatgptDesktop", date: date, configuration: configuration, calendar: calendar))
            let seconds = Int(configuration.threshold)
            for second in 0..<seconds { p.receive(sample(Double(second)), context: context) }
            check(p.presentation == nil, "Selected interval never proposes early: \(interval.rawValue)")
            p.receive(sample(Double(seconds)), context: context)
            check(p.presentation != nil, "Selected interval proposes at its threshold: \(interval.rawValue)")
        }
        p = UsageReminderPolicy(tracker: tracker())
        for second in 0...1200 { p.receive(sample(Double(second)), context: context) }
        p.setInterval(.minutes120)
        check(p.aggregate.seconds == 1200 && p.tracker.configuration.threshold == 7200, "Increasing interval retains elapsed usage")
        p.setInterval(.minutes30)
        check(p.aggregate.seconds == 1200 && p.presentation == nil, "Reducing interval retains elapsed usage without displaying immediately")
        for second in 1201...1801 { p.receive(sample(Double(second)), context: context) }
        let previousID = p.presentation!.id
        p.setInterval(.minutes180)
        check(p.presentation == nil && p.accept(id: previousID, time: 1802, context: context) == nil, "Changing interval invalidates an existing card")
        check(!p.tracker.cooldownAllows(date.addingTimeInterval(1801 + 10799)) && p.tracker.cooldownAllows(date.addingTimeInterval(1801 + 10800)),
              "Changing interval updates the minimum notice interval")
        p = UsageReminderPolicy(tracker: tracker())
        for second in 0...2400 { p.receive(sample(Double(second)), context: context) }
        context.eligible = false; p.setInterval(.minutes30)
        p.evaluate(time: 2400, date: date.addingTimeInterval(2400), context: context)
        check(p.presentation == nil && p.aggregate.seconds == 1800, "Lowering below accrued usage waits while settings are open")
        context.eligible = true
        p.evaluate(time: 2401, date: date.addingTimeInterval(2401), context: context)
        check(p.presentation != nil, "Retained usage can propose once the selected app and Home become eligible")
        // Regression: leave Squat on Settings, then spend 30 minutes in ChatGPT.
        // The previous Home-only eligibility silently discarded this candidate.
        let halfHour = UsageReminderConfiguration(interval: .minutes30)
        p = UsageReminderPolicy(tracker: UsageTimeTracker(provider: "chatgptDesktop", date: date, configuration: halfHour, calendar: calendar))
        context = UsageReminderContext(enabled: true, eligible: AppScreen.settings.allowsUsageReminder,
                                       targetIsFront: true, inputQuietTime: 3, target: 5)
        for second in 0...1800 { p.receive(sample(Double(second)), context: context) }
        check(p.presentation != nil, "Leaving Settings open in the background does not suppress a 30-minute invitation")
        check(p.accept(id: p.presentation!.id, time: 1801, context: context) != nil, "An invitation from background Settings remains actionable")
        check(AppScreen.result.allowsUsageReminder, "A background result page also permits the next break")
        for screen in [AppScreen.welcome, .prepare, .workout] {
            check(!screen.allowsUsageReminder, "Onboarding and camera sessions still suppress invitations")
        }
        p = UsageReminderPolicy(tracker: UsageTimeTracker(provider: "chatgptDesktop", date: date, configuration: halfHour, calendar: calendar))
        context.targetIsFront = false
        p.receive(sample(0), context: context)
        for second in 1...1800 { p.receive(sample(Double(second)), context: context) }
        check(p.presentation == nil, "An active Squat settings window cannot trigger an automatic card")
        check(UsageProgress(seconds: 1799, threshold: 1800) == UsageProgress(seconds: 1740, threshold: 1800), "Progress only changes at minute boundaries")
        check(UsageProgress(seconds: 1799, threshold: 1800).elapsedMinutes == 29, "Displayed usage never rounds up to an unreached threshold")
        check(UsageProgress(seconds: 1800, threshold: 1800).targetMinutes == 30, "Progress uses the actual configured interval")
        check(UsageProgress(seconds: .nan, threshold: .infinity).elapsedMinutes == 0, "Invalid progress values stay safe")
        print("UsageReminderChecks: \(checked) passed")
    }
}
