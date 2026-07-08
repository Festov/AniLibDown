import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.35
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -10
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var glowScale: CGFloat = 0.6
    @State private var glowOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var breathe = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.05),
                            .white.opacity(0.35),
                            .white.opacity(0.05)
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(ringRotation))
                .opacity(glowOpacity)
                .scaleEffect(glowScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .scaleEffect(glowScale)
                .opacity(glowOpacity * 0.9)

            VStack(spacing: 28) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .white.opacity(breathe ? 0.35 : 0.15), radius: breathe ? 20 : 8)
                    .scaleEffect(logoScale * (breathe ? 1.05 : 1))
                    .rotationEffect(.degrees(logoRotation))
                    .opacity(logoOpacity)

                Text("Спасибо, что выбираете нас!")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            withAnimation(.spring(response: 0.85, dampingFraction: 0.62)) {
                logoScale = 1
                logoOpacity = 1
                logoRotation = 0
                glowScale = 1.08
                glowOpacity = 1
            }

            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }

            withAnimation(.easeInOut(duration: 0.55).delay(0.45)) {
                textOpacity = 1
                textOffset = 0
            }

            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true).delay(0.7)) {
                breathe = true
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                await MainActor.run {
                    onFinished()
                }
            }
        }
    }
}

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if !showSplash {
                ContentView()
                    .transition(.opacity)
            }

            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
