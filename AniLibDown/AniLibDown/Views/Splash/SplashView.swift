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
    @State private var colorShift: Double = 0
    @State private var backgroundPulse = false
    @State private var textHue: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.78, green: 0.24, blue: 0.24).opacity(0.35 + colorShift * 0.25),
                                Color.white.opacity(0.12),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 90
                        )
                    )

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.78, green: 0.24, blue: 0.24).opacity(0.15),
                                .white.opacity(0.4),
                                Color(red: 0.9, green: 0.35, blue: 0.3).opacity(0.55),
                                .white.opacity(0.15),
                                Color(red: 0.78, green: 0.24, blue: 0.24).opacity(0.15)
                            ],
                            center: .center
                        ),
                        lineWidth: 2.5
                    )
                    .rotationEffect(.degrees(ringRotation))

                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color(red: 0.78, green: 0.24, blue: 0.24).opacity(breathe ? 0.45 : 0.2), radius: breathe ? 18 : 8)
                    .scaleEffect(logoScale * (breathe ? 1.04 : 1))
                    .rotationEffect(.degrees(logoRotation))
                    .opacity(logoOpacity)
            }
            .frame(width: 168, height: 168)
            .scaleEffect(glowScale)
            .opacity(glowOpacity)

            Text("Спасибо, что выбираете нас!")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(
                                hue: 0.0 + textHue * 0.04,
                                saturation: 0.35 + textHue * 0.45,
                                brightness: 0.95
                            ),
                            Color.white.opacity(0.9)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color(red: 0.78, green: 0.24, blue: 0.24).opacity(textOpacity * 0.55), radius: 12)
                .opacity(textOpacity)
                .offset(y: textOffset)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color.black
                RadialGradient(
                    colors: [
                        Color(red: 0.78, green: 0.24, blue: 0.24).opacity(backgroundPulse ? 0.28 : 0.08),
                        Color(red: 0.35, green: 0.05, blue: 0.08).opacity(backgroundPulse ? 0.35 : 0.12),
                        .clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
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

            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.45)) {
                colorShift = 1
                backgroundPulse = true
                textHue = 1
            }

            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.success)
                }
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
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var showSplash = true

    init() {
        _showSplash = State(initialValue: AppSettings.shared.isSplashEnabled)
    }

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
        .onChange(of: appSettings.isSplashEnabled) { _, isEnabled in
            if !isEnabled {
                showSplash = false
            }
        }
    }
}
