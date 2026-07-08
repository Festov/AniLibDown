import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0

    private let logoURL = URL(string: "https://cdn.anilibria.top/static/apple-touch-icon.png")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Group {
                    if let logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            default:
                                Image(systemName: "play.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.white)
                            }
                        }
                    } else {
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                Text("Спасибо, что выбираете нас!")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(textOpacity)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                logoScale = 1
                logoOpacity = 1
            }

            withAnimation(.easeInOut(duration: 0.5).delay(0.35)) {
                textOpacity = 1
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        onFinished()
                    }
                }
            }
        }
    }
}

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView {
                    showSplash = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
    }
}
