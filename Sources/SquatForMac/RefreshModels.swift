import Foundation
import CoreGraphics

/// Values derived from the supplied 402 × 706 canvas. Camera geometry is separate.
enum RefreshGeometry {
    static let home = CGSize(width: 402, height: 706)
    static let detail = CGSize(width: 802, height: 481)
    static let center = CGPoint(x: 200.0988006592, y: 265.0988006592)
    static let theta2 = atan2(319.5 - center.y, 116.5988 - center.x) * 180 / .pi
    static let radius = hypot(116.5988 - center.x, 319.5 - center.y)
    static func angle(_ n: Int) -> Double {
        let v = min(30, max(1, n))
        return v == 1 ? 135 : theta2 + (405 - theta2) * Double(v - 2) / 28
    }
    static func marker(_ n: Int) -> CGPoint {
        let a = angle(n) * .pi / 180
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
    static func value(_ point: CGPoint, previous: Double?) -> (Int, Double) {
        var a = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if let p = previous { a += round((p - a) / 360) * 360 }
        else { while a < 135 { a += 360 }; if a > 405 { a = a < 450 ? 405 : 135 } }
        let safe = min(405, max(135, a))
        let n = safe < theta2 ? 1 + (safe - 135) / (theta2 - 135) : 2 + (safe - theta2) * 28 / (405 - theta2)
        return (min(30, max(1, Int(n.rounded()))), a)
    }
    static func countdownArc(_ remaining: Double) -> Double {
        let r = min(10, max(0, remaining))
        return r <= 7 ? 270 * r / 7 : 270 + 90 * (r - 7) / 3
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds.isFinite ? min(seconds, 3_600_000_000) : 0) / 60)
        return String(format: "%02dh%02dm", minutes / 60, minutes % 60)
    }
}

struct RefreshDayUsage: Codable, Equatable {
    var ai: [String: Double] = [:]
    var desk: Double = 0
    var measuredAI: Set<String> = []
    var measuredDesk = false
    var timeZoneIdentifier: String?
    enum CodingKeys: String, CodingKey { case ai, desk, measuredAI, measuredDesk, timeZoneIdentifier }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ai = try c.decodeIfPresent([String: Double].self, forKey: .ai) ?? [:]
        desk = try c.decodeIfPresent(Double.self, forKey: .desk) ?? 0
        measuredAI = try c.decodeIfPresent(Set<String>.self, forKey: .measuredAI) ?? Set(ai.filter { $0.value > 0 }.keys)
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        measuredDesk = try c.decodeIfPresent(Bool.self, forKey: .measuredDesk) ?? (desk > 0)
    }
}

/// Only daily totals and reminder progress survive a restart. No application timeline.
struct RefreshUsageLedger: Codable {
    var days: [String: RefreshDayUsage] = [:]
    var reminder: [String: Double] = [:]
    var pausedDay: String?
    var lastNotice: Date?
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    func total(_ selected: Set<AIProvider>, day: String) -> Double {
        selected.reduce(0) { $0 + max(0, days[day]?.ai[$1.rawValue] ?? 0) }
    }
    func elapsed(_ selected: Set<AIProvider>) -> Double {
        selected.reduce(0) { $0 + max(0, reminder[$1.rawValue] ?? 0) }
    }
    mutating func add(_ seconds: Double, day: String, provider: AIProvider?, countAI: Bool, countDesk: Bool) {
        guard seconds.isFinite, seconds > 0, seconds <= 5, countDesk || (countAI && provider != nil) else { return }
        var value = days[day] ?? .init()
        if value.timeZoneIdentifier == nil { value.timeZoneIdentifier = TimeZone.current.identifier }
        if countDesk { value.desk += seconds; value.measuredDesk = true }
        if countAI, let provider {
            value.ai[provider.rawValue, default: 0] += seconds; value.measuredAI.insert(provider.rawValue)
            reminder[provider.rawValue, default: 0] += seconds
        }
        days[day] = value
    }
    mutating func consume(at date: Date) { reminder = [:]; lastNotice = date }
}

enum RefreshNotificationStyle: String, CaseIterable { case primary, countdown }
struct RefreshInvitation: Identifiable {
    let id: UUID
    let style: RefreshNotificationStyle
    let target: Int
    let source: String
    let seconds: Double
    let shownAt: Double
    let expiresAt: Double
    let isTest: Bool
}
