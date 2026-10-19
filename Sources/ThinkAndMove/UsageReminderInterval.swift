import Foundation

enum UsageReminderInterval: Int, CaseIterable, Identifiable {
    case minutes30 = 30, minutes60 = 60, minutes90 = 90, minutes120 = 120, minutes180 = 180
    static func normalized(_ value: Int) -> Self {
        allCases.min { a,b in abs(Double(a.rawValue)-Double(value)) < abs(Double(b.rawValue)-Double(value)) } ?? .minutes60
    }
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}
