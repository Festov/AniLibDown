import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var message: String?
    @Published var isError = false

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, isError: Bool = false) {
        dismissTask?.cancel()
        self.message = message
        self.isError = isError
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            if self.message == message {
                self.message = nil
            }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = center.message {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(center.isError ? Color.red.opacity(0.92) : Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: center.message)
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
