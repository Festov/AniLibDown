import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var login = ""
    @State private var password = ""

    private let brandRed = Color(red: 0.78, green: 0.24, blue: 0.24)
    private let brandDeep = Color(red: 0.35, green: 0.05, blue: 0.08)

    private var canSubmit: Bool {
        !login.isEmpty && !password.isEmpty && !authService.isLoading
    }

    var body: some View {
        ZStack {
            AniLibertyBackground()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: brandRed.opacity(0.45), radius: 16)

                    Text("AniLibDown")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Войдите в аккаунт AniLiberty")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                VStack(spacing: 14) {
                    VStack(spacing: 12) {
                        TextField("Логин", text: $login)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submitLogin()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [brandRed, brandDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            if authService.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Войти")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.55)
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submitLogin() {
        guard canSubmit else { return }
        Task {
            await authService.login(login: login, password: password)
        }
    }
}

struct AniLibertyBackground: View {
    private let brandRed = Color(red: 0.78, green: 0.24, blue: 0.24)
    private let brandDeep = Color(red: 0.35, green: 0.05, blue: 0.08)

    @State private var backgroundPulse = false
    @State private var orbDrift = false
    @State private var colorShift: Double = 0

    var body: some View {
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
                    brandRed.opacity(0.28 + colorShift * 0.12),
                    brandDeep.opacity(0.35),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.35, blue: 0.28).opacity(backgroundPulse ? 0.22 : 0.08),
                    .clear
                ],
                center: orbDrift ? .topTrailing : .topLeading,
                startRadius: 10,
                endRadius: 280
            )
            .offset(x: orbDrift ? 40 : -30, y: orbDrift ? -60 : 20)

            RadialGradient(
                colors: [
                    brandRed.opacity(backgroundPulse ? 0.16 : 0.06),
                    .clear
                ],
                center: orbDrift ? .bottomLeading : .bottomTrailing,
                startRadius: 8,
                endRadius: 240
            )
            .offset(x: orbDrift ? -50 : 35, y: orbDrift ? 80 : 40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                backgroundPulse = true
                orbDrift = true
                colorShift = 1
            }
        }
    }
}
