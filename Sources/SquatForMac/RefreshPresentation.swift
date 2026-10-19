import SwiftUI

/// Content remains hidden until the native window has finished changing size.
@MainActor final class RefreshPresentation: ObservableObject {
    @Published private(set) var screen: AppScreen = .home
    @Published private(set) var opacity = 1.0
    @Published private(set) var isTransitioning = false
    private var generation = UUID()
    private var pending: Task<Void, Never>?
    func show(_ next: AppScreen, animated: Bool, resize: @escaping (@escaping () -> Void) -> Void) {
        pending?.cancel()
        let request = UUID(); generation = request
        guard animated else {
            screen = next; opacity = 1; isTransitioning = false
            resize({}); return
        }
        isTransitioning = true
        withAnimation(.easeOut(duration: 0.08)) { opacity = 0 }
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            guard let self, self.generation == request else { return }
            self.screen = next
            resize { [weak self] in
                guard let self, self.generation == request else { return }
                withAnimation(.easeOut(duration: 0.14)) { self.opacity = 1 }
                self.pending = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
                    guard let self, self.generation == request else { return }
                    self.isTransitioning = false
                }
            }
        }
    }
}
