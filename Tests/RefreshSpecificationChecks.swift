import Foundation

@main enum RefreshSpecificationChecks {
    static func main() throws {
        var checked = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(),name); checked += 1 }
        let marker = RefreshGeometry.marker(2)
        check(abs(marker.x - 116.5988) < 0.001 && abs(marker.y - 319.5) < 0.001, "Original 2-rep calibration")
        check(RefreshGeometry.angle(-1) == 135 && RefreshGeometry.angle(99) == 405, "Clamp every geometry input")
        for value in 1...30 {
            check(RefreshGeometry.value(RefreshGeometry.marker(value),previous: RefreshGeometry.angle(value)).0 == value,"Round-trip calibrated ring")
        }
        check(RefreshGeometry.countdownArc(7) == 270,"7-second reference is 270 degrees")
        check(RefreshGeometry.countdownArc(10) == 360 && RefreshGeometry.countdownArc(0) == 0,"Countdown endpoints")
        check(RefreshGeometry.duration(3600) == "01h00m", "Duration formatting")
        check(RefreshGeometry.duration(-1) == "00h00m" && RefreshGeometry.duration(.infinity) == "00h00m","Nonfinite durations")
        var ledger = RefreshUsageLedger()
        let day = "2026-10-18"
        var withoutConsent = RefreshUsageLedger()
        withoutConsent.add(5, day: day, provider: .chatgptDesktop, countAI: false, countDesk: false)
        check(withoutConsent.days.isEmpty && withoutConsent.reminder.isEmpty, "No usage rows are created without collection consent")
        for _ in 0..<360 { ledger.add(5,day: day,provider: .chatgptDesktop,countAI: true,countDesk: true) }
        for _ in 0..<360 { ledger.add(5,day: day,provider: .claudeDesktop,countAI: true,countDesk: true) }
        check(ledger.elapsed([.chatgptDesktop,.claudeDesktop]) == 3600,"30+30-minute aggregation")
        check(ledger.total([.chatgptDesktop],day: day) == 1800,"Off provider excluded without deleting its total")
        check(ledger.days[day]?.desk == 3600,"AI usage is included in PC time")
        ledger.add(300,day: day,provider: .chatgptDesktop,countAI: true,countDesk: true)
        check(ledger.days[day]?.desk == 3600,"Observation gaps do not count")
        ledger.consume(at: Date())
        check(ledger.elapsed([.chatgptDesktop,.claudeDesktop]) == 0,"Only reminder progress resets")
        check(ledger.total([.chatgptDesktop,.claudeDesktop],day: day) == 3600 && ledger.days[day]?.desk == 3600,"Notification does not erase daily totals")
        ledger.add(5,day: day,provider: nil,countAI: true,countDesk: true)
        check(ledger.days[day]?.desk == 3605 && ledger.total([.chatgptDesktop,.claudeDesktop],day: day) == 3600,"Non-AI PC usage is separate")
        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(RefreshUsageLedger.self,from: data)
        check(restored.days[day] == ledger.days[day],"Daily totals survive persistence")
        check(!String(decoding: data,as: UTF8.self).contains("sessionTag"),"No conversation identifiers in usage persistence")
        print("PASS: \(checked) refresh specification checks")
    }
}
