import Foundation

@main @MainActor enum ProgressPerformanceChecks {
    struct LegacyEvent: Codable { let sessionID: UUID; let recordedAt: Date }
    struct LegacyArchive: Encodable {
        let version = 1
        let sessions: [WorkoutSession]
        let events: [LegacyEvent]
        let activeSessionID: UUID? = nil
        let legacyTotal = 0
    }

    static func main() async throws {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checked += 1
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SquatProgressPerformanceChecks-\(UUID().uuidString)", isDirectory: true)
        let suite = "Squat.ProgressPerformanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let calendar = ProgressCalendarModel.localCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        func date(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        let anchor = date(10, 15)
        let bounds = ProgressCalendarModel.bounds(period: .year, anchor: anchor, calendar: calendar)
        let sessionID = UUID()
        var calendarDates: [Date] = []
        var day = bounds.0
        while day <= bounds.1 {
            calendarDates.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        let observations = calendarDates.map { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0)! }
        let events = (0..<50_000).map { LegacyEvent(sessionID: sessionID, recordedAt: observations[$0 % observations.count]) }
        let lastObservation = observations.last!
        let session = WorkoutSession(id: sessionID, startedAt: bounds.0, endedAt: lastObservation,
                                     reps: events.count, mode: "face", completed: false)
        let raw = try JSONEncoder().encode(LegacyArchive(sessions: [session], events: events))
        defaults.set(raw, forKey: "thinkAndMove.workoutHistory.v1")
        let history = WorkoutHistory(defaults: defaults, calendar: calendar, now: { anchor }, databaseURL: folder.appendingPathComponent("workout.sqlite"))
        check(history.canRecord && history.lifetimeReps == 50_000, "Large synthetic archive loads without dropping counts")
        check(history.dayCountIndexRebuildCount == 1, "Loading creates the daily index once")
        let expectedCounts = Dictionary(grouping: events, by: { calendar.startOfDay(for: $0.recordedAt) }).mapValues(\.count)
        let indexed = history.dayCounts(from: bounds.0, through: bounds.1)
        check(indexed.count == 365 && indexed.allSatisfy { $0.count == expectedCounts[$0.date, default: 0] }, "Indexed calendar days match all 50,000 source observations")

        let cache = ProgressDataCache()
        let queriesBeforeWeek = history.dayCountQueryCount
        let week = cache.model(history: history, period: .week, anchor: anchor, today: anchor)
        check(week.days.count == 7 && cache.yearBuildCount == 1 && history.dayCountQueryCount == queriesBeforeWeek + 2, "Weekly rendering shares the annual color scale and queries seven indexed days")
        let queriesBeforePointer = history.dayCountQueryCount
        let rebuildsBeforePointer = history.dayCountIndexRebuildCount
        for index in 0..<1_000 {
            // Selection and pointer movement are intentionally absent from the projection API.
            let selectedDate = calendarDates[index % calendarDates.count]
            _ = selectedDate
            _ = cache.model(history: history, period: .week, anchor: anchor, today: anchor)
        }
        check(cache.modelBuildCount == 1 && history.dayCountQueryCount == queriesBeforePointer, "Repeated interaction lookups reuse the immutable weekly model")
        check(history.dayCountIndexRebuildCount == rebuildsBeforePointer, "Interaction lookups never rescan the recorded events")

        let month = cache.model(history: history, period: .month, anchor: anchor, today: anchor)
        let queriesBeforeYear = history.dayCountQueryCount
        let year = cache.model(history: history, period: .year, anchor: anchor, today: anchor)
        check(cache.yearBuildCount == 1 && history.dayCountQueryCount == queriesBeforeYear, "Month and Year share one annual count snapshot")
        check(month.annualMaximum == year.annualMaximum && year.annualMaximum == expectedCounts.values.max(), "Month and Year use the same annual intensity scale")
        let expectedYearTotal = expectedCounts.filter { $0.key <= calendar.startOfDay(for: anchor) }.values.reduce(0, +)
        check(year.total == expectedYearTotal, "Cached totals exclude future dates without losing stored observations")
        let revisionBeforeStatus = history.historyRevision
        let buildsBeforeStatus = cache.modelBuildCount
        history.dailyGoal = 42
        let initiallySaved = await history.flush()
        _ = cache.model(history: history, period: .year, anchor: anchor, today: anchor)
        check(initiallySaved && history.historyRevision == revisionBeforeStatus && cache.modelBuildCount == buildsBeforeStatus, "Preferences and save status do not invalidate count projections")

        let rebuildsBeforeRep = history.dayCountIndexRebuildCount
        let todayBeforeRep = history.todayReps
        history.recordRep(at: anchor, mode: "face")
        check(history.historyRevision == revisionBeforeStatus + 1 && history.dayCountIndexRebuildCount == rebuildsBeforeRep, "A recorded movement updates one day without rebuilding the event index")
        check(history.todayReps == todayBeforeRep + 1 && history.todaySessions == 2 && history.lifetimeReps == 50_001, "Incremental totals and session-day counts update immediately")
        let changedMonth = cache.model(history: history, period: .month, anchor: anchor, today: anchor)
        let changedYear = cache.model(history: history, period: .year, anchor: anchor, today: anchor)
        check(changedMonth.total == month.total + 1 && changedYear.total == year.total + 1 && cache.yearBuildCount == 2, "New records invalidate projections once and still share annual data")

        let revisionBeforeTimeZone = history.historyRevision
        let rebuildsBeforeTimeZone = history.dayCountIndexRebuildCount
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        history.refreshCalendarForCurrentTimeZone(tokyo)
        let tokyoCalendar = ProgressCalendarModel.localCalendar(timeZone: tokyo)
        let tokyoBounds = ProgressCalendarModel.bounds(period: .year, anchor: anchor, calendar: tokyoCalendar)
        var tokyoExpected = Dictionary(grouping: events, by: { tokyoCalendar.startOfDay(for: $0.recordedAt) }).mapValues(\.count)
        tokyoExpected[tokyoCalendar.startOfDay(for: anchor), default: 0] += 1
        let tokyoDays = history.dayCounts(from: tokyoBounds.0, through: tokyoBounds.1)
        check(history.historyRevision == revisionBeforeTimeZone + 1 && history.dayCountIndexRebuildCount == rebuildsBeforeTimeZone + 1, "A time-zone change rebuilds calendar-day boundaries once")
        check(tokyoDays.allSatisfy { $0.count == tokyoExpected[$0.date, default: 0] }, "Rebuilt day counts follow the new time zone, including year boundaries")
        history.refreshCalendarForCurrentTimeZone(tokyo)
        check(history.historyRevision == revisionBeforeTimeZone + 1 && history.dayCountIndexRebuildCount == rebuildsBeforeTimeZone + 1, "An unchanged time zone cannot trigger a redundant event scan")
        _ = cache.model(history: history, period: .month, anchor: anchor, today: anchor)
        let beforeMidnight = cache.modelBuildCount
        let tomorrow = tokyoCalendar.date(byAdding: .day, value: 1, to: anchor)!
        let nextDay = cache.model(history: history, period: .month, anchor: anchor, today: tomorrow)
        check(cache.modelBuildCount == beforeMidnight + 1 && nextDay.today == tokyoCalendar.startOfDay(for: tomorrow), "Passing midnight invalidates future-day eligibility without a new rep")

        let otherSuite = "Squat.ProgressPerformanceChecks.Other.\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuite)!
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        let other = WorkoutHistory(defaults: otherDefaults, calendar: calendar, now: { anchor }, databaseURL: folder.appendingPathComponent("other.sqlite"))
        let otherYear = cache.model(history: other, period: .year, anchor: anchor, today: anchor)
        check(otherYear.total == 0 && otherYear.annualMaximum == 0, "Changing history sources cannot reuse another database's cached records")

        // Compare the old full-event projection algorithm with cache hits using the same synthetic input.
        // Startup migration/index construction is deliberately outside both interaction timings.
        let comparisonEvents = events + [LegacyEvent(sessionID: UUID(), recordedAt: anchor)]
        func previousProjection() -> ProgressCalendarModel {
            var counts: [Date: Int] = [:]
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: bounds.1)!
            for event in comparisonEvents where event.recordedAt >= bounds.0 && event.recordedAt < exclusiveEnd {
                counts[calendar.startOfDay(for: event.recordedAt), default: 0] += 1
            }
            var filled: [Date: Int] = [:]
            var date = bounds.0
            while date <= bounds.1 {
                filled[date] = counts[date, default: 0]
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
            return ProgressCalendarModel(period: .year, anchor: anchor, counts: filled, today: anchor, calendar: calendar)
        }
        let benchmarkCache = ProgressDataCache()
        // The populated source has changed by one rep and time zone; restore only its display zone
        // and use the same calendar/count input for a fair checksum comparison.
        history.refreshCalendarForCurrentTimeZone(calendar.timeZone)
        let iterations = 100
        var oldChecksum = 0
        let oldStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations { oldChecksum &+= previousProjection().total }
        let oldDuration = ProcessInfo.processInfo.systemUptime - oldStart
        let queryCountBeforeBenchmark = history.dayCountQueryCount
        var cachedChecksum = 0
        let cachedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            cachedChecksum &+= benchmarkCache.model(history: history, period: .year, anchor: anchor, today: anchor).total
        }
        let cachedDuration = ProcessInfo.processInfo.systemUptime - cachedStart
        check(cachedChecksum == oldChecksum, "Old and indexed projections agree on the same synthetic observations")
        check(benchmarkCache.modelBuildCount == 1 && benchmarkCache.yearBuildCount == 1 && history.dayCountQueryCount == queryCountBeforeBenchmark + 1, "One hundred render lookups build and query the annual projection once")
        print("Synthetic projection benchmark: \(comparisonEvents.count) events × \(iterations) lookups; previous scan \(String(format: "%.4f", oldDuration))s, indexed cache \(String(format: "%.4f", cachedDuration))s. This is not an app FPS measurement.")
        let interactionCache = ProgressDataCache()
        let labels = ProgressRenderCache()
        var switching: [Double] = [], navigation: [Double] = []
        for index in 0..<20 {
            let begin = ProcessInfo.processInfo.systemUptime
            let projection = interactionCache.model(history: history, period: index.isMultiple(of: 2) ? .week : .month, anchor: anchor, today: anchor)
            _ = labels.snapshot(model: projection, revision: history.historyRevision, japanese: false, locale: Locale(identifier: "en_US"))
            switching.append((ProcessInfo.processInfo.systemUptime - begin) * 1000)
        }
        for index in 1...20 {
            let begin = ProcessInfo.processInfo.systemUptime
            let moved = calendar.date(byAdding: .month, value: -index, to: anchor)!
            let projection = interactionCache.model(history: history, period: .month, anchor: moved, today: anchor)
            _ = labels.snapshot(model: projection, revision: history.historyRevision, japanese: false, locale: Locale(identifier: "en_US"))
            navigation.append((ProcessInfo.processInfo.systemUptime - begin) * 1000)
        }
        func p95(_ values: [Double]) -> Double { values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1] }
        print("Synthetic projection + label p95, 20 operations each: period switch \(String(format: "%.3f", p95(switching)))ms; month navigation \(String(format: "%.3f", p95(navigation)))ms. Excludes SwiftUI layout, rendering and input dispatch.")
        print("PASS: \(checked) progress performance checks")
    }
}
