import Foundation
@main struct Checks {
    static func main() throws {
        var n = 0
        func check(_ v: @autoclosure () -> Bool,_ message: String) { n += 1; if !v() { fatalError(message) } }
        var c = RefreshReminderCycle()
        check(c.candidate(now: 0,regularReady: false) == nil,"No notification before threshold")
        check(c.candidate(now: 0,regularReady: true) == .primary,"First ordinary opportunity")
        check(!c.pending,"A failed display cannot create a cycle")
        c.displayed(.primary,at: 100)
        check(c.followupDeadline == 2800,"45 minutes begins at successful display")
        check(c.candidate(now: 1899,regularReady: false) == nil,"Wait before next regular time")
        check(c.candidate(now: 1900,regularReady: true) == .countdown,"30 minute next opportunity replaces ordinary notification")
        c.displayed(.countdown,at: 1900)
        check(!c.pending && c.candidate(now: 2800,regularReady: false) == nil,"Cancelled 45 minute reservation cannot fire")
        check(c.candidate(now: 3700,regularReady: true) == .primary,"New cycle starts with ordinary card")
        c.displayed(.primary,at: 0)
        check(c.candidate(now: 2699,regularReady: false) == nil,"No early followup")
        check(c.candidate(now: 2700,regularReady: false) == .countdown,"Wall deadline does not require send")
        check(c.candidate(now: 2700,regularReady: true) == .countdown,"Simultaneous conditions yield one countdown")
        check(c.candidate(now: 4200,regularReady: false) == .countdown,"One pending invitation after sleep/ineligible interval")
        c.cancel()
        check(!c.pending && c.candidate(now: 9000,regularReady: false) == nil,"Successful exercise or configuration cancellation clears reservation")
        let restarted = RefreshReminderCycle()
        check(!restarted.pending,"Restart never replays an old cycle")
        c.displayed(.primary,at: 0)
        check(c.candidate(now: 2100,regularReady: true) == .countdown,"afterSend next event can precede 45 minute deadline")
        c.displayed(.countdown,at: 2100)
        check(c.candidate(now: 2700,regularReady: false) == nil,"No third follow-up")
        var ledger = RefreshUsageLedger()
        check(ledger.days.isEmpty,"No fabricated historical zero")
        ledger.add(1,day:"2026-10-18",provider:.chatgptDesktop,countAI:true,countDesk:true)
        check(ledger.days["2026-10-18"]?.measuredAI.contains("chatgptDesktop") == true,"Real sample records measurement availability")
        check(ledger.days["2026-10-18"]?.measuredDesk == true,"Desk measurement is independent metadata")
        ledger.consume(at:Date())
        check(ledger.elapsed([.chatgptDesktop]) == 0 && ledger.total([.chatgptDesktop],day:"2026-10-18") == 1,"Notification consumption preserves daily data")
        let legacy = Data("{\"ai\":{\"chatgptDesktop\":0,\"claudeDesktop\":60},\"desk\":0}".utf8)
        let value = try JSONDecoder().decode(RefreshDayUsage.self,from: legacy)
        check(value.measuredAI == ["claudeDesktop"] && !value.measuredDesk,"Legacy zero without proof stays unknown")
        let restored = try JSONDecoder().decode(RefreshUsageLedger.self,from: JSONEncoder().encode(ledger))
        check(restored.days == ledger.days,"Measurement metadata survives restart")
        for (raw,expected) in [(240,180),(-1,30),(105,90),(179,180),(60,60),(75,60)] {
            check(UsageReminderInterval.normalized(raw).rawValue == expected,"Interval normalizes invalid saved input and tie to lower")
        }
        check(ledger.days["2026-10-18"]?.timeZoneIdentifier == TimeZone.current.identifier,"New measurements retain their local timezone")
        print("PASS: \(n) v2.7 cycle/measurement checks")
    }
}
