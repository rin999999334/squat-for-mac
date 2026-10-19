import Foundation

enum RecognitionIssue: String, Equatable {
    case noFace, multipleFaces, unreadableFace, noBody, cameraUnavailable, cameraStartFailed, cameraInterrupted, permissionDenied, storageFailed
    var japaneseText: String {
        switch self {
        case .noFace: return "顔を画面に映してください。脚は映らなくても大丈夫。"
        case .multipleFaces: return "複数の顔が見えています。1人だけ映してください。"
        case .unreadableFace: return "顔を読み取れませんでした。位置や明るさを調整してください。"
        case .noBody: return "横向きで腰・膝・足首を映してください。"
        case .cameraUnavailable: return "カメラを開けません。他のアプリで使用中か確認してください。"
        case .cameraStartFailed: return "カメラを開始できませんでした。"
        case .cameraInterrupted: return "カメラが中断されました。他のカメラアプリを閉じて再開してください。"
        case .permissionDenied: return "システム設定のプライバシーとセキュリティ → カメラでSquatを許可してください。"
        case .storageFailed: return "記録を保存できませんでした。保存を再試行してから再開してください。"
        }
    }
    var englishText: String {
        switch self {
        case .noFace: return "Keep your face in view. Your legs can stay out of frame."
        case .multipleFaces: return "More than one face is visible. Keep only one person in view."
        case .unreadableFace: return "Move into better light and keep your face in view."
        case .noBody: return "Turn sideways and keep your hip, knee and ankle in view."
        case .cameraUnavailable: return "Camera unavailable. Check whether another app is using it."
        case .cameraStartFailed: return "The camera could not start. Try again."
        case .cameraInterrupted: return "Camera interrupted. Close other camera apps and try again."
        case .permissionDenied: return "Allow Squat in System Settings → Privacy & Security → Camera."
        case .storageFailed: return "Your record could not be saved. Retry saving before starting again."
        }
    }
}
