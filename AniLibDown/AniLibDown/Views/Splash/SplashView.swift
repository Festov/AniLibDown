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
    @State private var outerRingRotation: Double = 0
    @State private var breathe = false
    @State private var colorShift: Double = 0
    @State private var backgroundPulse = false
    @State private var textHue: Double = 0
    @State private var orbDrift = false
    @State private var wavePhase: CGFloat = 0

    private let brandRed = Color(red: 0.78, green: 0.24, blue: 0.24)
    private let brandDeep = Color(red: 0.35, green: 0.05, blue: 0.08)

    var body: some View {
        ZStack {
            splashBackground

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    brandRed.opacity(0.35 + colorShift * 0.25),
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
                                    brandRed.opacity(0.15),
                                    .white.opacity(0.4),
                                    Color(red: 0.9, green: 0.35, blue: 0.3).opacity(0.55),
                                    .white.opacity(0.15),
                                    brandRed.opacity(0.15)
                                ],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .rotationEffect(.degrees(ringRotation))

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .clear,
                                    brandRed.opacity(0.35),
                                    .clear,
                                    Color.white.opacity(0.25),
                                    .clear
                                ],
                                center: .center
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 188, height: 188)
                        .rotationEffect(.degrees(outerRingRotation))

                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: brandRed.opacity(breathe ? 0.45 : 0.2), radius: breathe ? 18 : 8)
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
                    .shadow(color: brandRed.opacity(textOpacity * 0.55), radius: 12)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
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

            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                outerRingRotation = -360
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

            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.2)) {
                orbDrift = true
            }

            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }

            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await playSplashHapticPattern()
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                await MainActor.run {
                    onFinished()
                }
            }
        }
    }

    private var splashBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    brandDeep.opacity(backgroundPulse ? 0.85 : 0.55),
                    Color.black
                ],
                startPoint: orbDrift ? .topLeading : .top,
                endPoint: orbDrift ? .bottomTrailing : .bottom
            )

            RadialGradient(
                colors: [
                    brandRed.opacity(backgroundPulse ? 0.32 : 0.1),
                    brandDeep.opacity(backgroundPulse ? 0.4 : 0.15),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.35, blue: 0.28).opacity(backgroundPulse ? 0.22 : 0.06),
                    .clear
                ],
                center: orbDrift ? .topTrailing : .topLeading,
                startRadius: 10,
                endRadius: 280
            )
            .offset(x: orbDrift ? 40 : -30, y: orbDrift ? -60 : 20)

            RadialGradient(
                colors: [
                    brandRed.opacity(backgroundPulse ? 0.18 : 0.05),
                    .clear
                ],
                center: orbDrift ? .bottomLeading : .bottomTrailing,
                startRadius: 8,
                endRadius: 240
            )
            .offset(x: orbDrift ? -50 : 35, y: orbDrift ? 80 : 40)

            ForEach(0..<18, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(Double(index % 3 + 1) * 0.06))
                    .frame(width: CGFloat(4 + (index % 4) * 2))
                    .offset(
                        x: CGFloat((index * 37) % 180) - 90 + (orbDrift ? 12 : -8),
                        y: CGFloat((index * 53) % 320) - 160 + wavePhase * 24
                    )
                    .blur(radius: 0.5)
            }

            WaveGlow(phase: wavePhase)
                .opacity(backgroundPulse ? 0.35 : 0.15)
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func playSplashHapticPattern() async {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let light = UIImpactFeedbackGenerator(style: .light)
        heavy.prepare()
        medium.prepare()
        light.prepare()

        let pulses: [(UIImpactFeedbackGenerator, CGFloat, UInt64)] = [
            (heavy, 1.0, 0),
            (medium, 0.85, 90_000_000),
            (medium, 0.9, 90_000_000),
            (light, 0.75, 80_000_000),
            (medium, 0.95, 90_000_000),
            (heavy, 1.0, 100_000_000),
            (medium, 0.8, 90_000_000),
            (light, 0.7, 80_000_000),
            (medium, 0.85, 90_000_000),
            (heavy, 0.9, 110_000_000)
        ]

        for (generator, intensity, delay) in pulses {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            generator.impactOccurred(intensity: intensity)
        }
    }
}

private struct WaveGlow: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.72))
                path.addCurve(
                    to: CGPoint(x: width, y: height * 0.68),
                    control1: CGPoint(x: width * (0.25 + phase * 0.1), y: height * (0.62 - phase * 0.08)),
                    control2: CGPoint(x: width * (0.75 - phase * 0.1), y: height * (0.78 + phase * 0.06))
                )
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.24, blue: 0.24).opacity(0.18),
                        Color(red: 0.45, green: 0.08, blue: 0.12).opacity(0.08),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
