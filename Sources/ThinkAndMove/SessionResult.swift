import Foundation

enum AppScreen: Equatable {
    case welcome, home, settings, history, prepare, workout, result

    /// A foreground target app already excludes active interaction with Squat.
    var allowsUsageReminder: Bool {
        switch self {
        case .home, .settings, .history, .result: return true
        case .welcome, .prepare, .workout: return false
        }
    }
}

struct SessionResult: Identifiable, Equatable {
    let id: UUID
    let count: Int
    let target: Int
    let duration: TimeInterval
    let completed: Bool
    let isDemo: Bool
}
