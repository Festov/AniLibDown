import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var login = ""
    @State private var password = ""

    private let brandRed = Color(red: 0.78, green: 0.24, blue: 0.24)
    private let brandDeep = Color(red: 0.35, green: 0.05, blue: 0.08)

    var body: some View {
        ZStack {
            AniLibertyBackground()

            ScrollView {
                VStack(spacing: 28) {
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
                    .padding(.top, 24)

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
                            Task {
                                await authService.login(login: login, password: password)
                            }
                        } label: {
                            Group {
                                if authService.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Войти")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [brandRed, brandDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .disabled(login.isEmpty || password.isEmpty || authService.isLoading)
                        .opacity(login.isEmpty || password.isEmpty || authService.isLoading ? 0.55 : 1)
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
                }
                .padding(.vertical, 32)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct AniLibertyBackground: View {
    private let brandRed = Color(red: 0.78, green: 0.24, blue: 0.24)
    private let brandDeep = Color(red: 0.35, green: 0.05, blue: 0.08)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, brandDeep.opacity(0.85), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [brandRed.opacity(0.28), brandDeep.opacity(0.35), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [Color(red: 0.95, green: 0.35, blue: 0.28).opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}
