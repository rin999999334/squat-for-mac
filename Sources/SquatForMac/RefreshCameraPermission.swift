import AppKit
import AVFoundation

/// Every user-facing start path checks permission before changing to the existing camera screen.
@MainActor func refreshStartWithPermission(coordinator: AppCoordinator, settings: AppSettings, target: Int? = nil) {
    guard !coordinator.store.active, coordinator.store.history.canRecord else { return }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: coordinator.start(target: target)
    case .notDetermined:
        let alert = NSAlert()
        alert.messageText = settings.t("カメラで顔の上下を数えます。", "Count your squats with the camera.")
        alert.informativeText = settings.t("映像は保存しません。", "Video is never saved or sent.")
        alert.addButton(withTitle: settings.t("カメラを使う", "Use camera")); alert.addButton(withTitle: settings.t("キャンセル", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { coordinator.start(target: target) }
                else { coordinator.goHome() }
            }
        }
    default:
        coordinator.goHome()
        let alert = NSAlert(); alert.messageText = settings.t("カメラの使用が許可されていません。", "Camera access is not allowed.")
        alert.informativeText = settings.t("システム設定のプライバシーとセキュリティから許可できます。", "Allow camera access in System Settings → Privacy & Security.")
        alert.addButton(withTitle: settings.t("システム設定を開く", "Open System Settings")); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }
}
