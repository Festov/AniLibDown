import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section {
                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        Label("Уведомления", systemImage: "bell")
                    }
                    NavigationLink {
                        PlaybackSettingsView()
                    } label: {
                        Label("Просмотр", systemImage: "play.rectangle")
                    }
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Оформление", systemImage: "paintbrush")
                    }
                    NavigationLink {
                        DownloadsSettingsView()
                    } label: {
                        Label("Загрузки", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        CollectionSettingsView()
                    } label: {
                        Label("Коллекция", systemImage: "heart.text.square")
                    }
                    NavigationLink {
                        ShikimoriSettingsView()
                    } label: {
                        Label("Shikimori", systemImage: "link.circle")
                    }
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        Label("Память и кеш", systemImage: "internaldrive")
                    }
                }

                Section("Поддержать проект AniLiberty") {
                    Link(destination: URL(string: "https://www.patreon.com/aniliberty")!) {
                        Label {
                            Text("Patreon")
                        } icon: {
                            PatreonGlyph()
                                .frame(width: 18, height: 18)
                        }
                    }
                    Link(destination: URL(string: "https://boosty.to/aniliberty")!) {
                        Label {
                            Text("Boosty")
                        } icon: {
                            BoostyGlyph()
                                .frame(width: 18, height: 18)
                        }
                    }
                }

                Section {
                    Text(AppVersion.profileLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(L10n.profile)
            .sheet(isPresented: $showLogin) {
                NavigationStack {
                    LoginView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { showLogin = false }
                            }
                        }
                }
                .environmentObject(authService)
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated { showLogin = false }
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section("Аккаунт AniLiberty") {
            if let profile = authService.profile {
                HStack(spacing: 12) {
                    profileAvatar(for: profile)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.nickname)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let login = profile.login, login != profile.nickname {
                            Text("@\(login)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let email = profile.email, !email.isEmpty {
                            Text(email)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                    Button("Выйти", role: .destructive) {
                        Task { await authService.logout() }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }

            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Вход не обязателен. Без аккаунта доступны каталог, расписание, плеер и загрузки; коллекция AniLiberty — после входа.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Войти в AniLiberty") {
                        showLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private func profileAvatar(for profile: UserProfile) -> some View {
        if let avatarPath = profile.avatar?.displayURL,
           let avatarURL = APIConfig.mediaURL(for: avatarPath) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    avatarFallback
                case .empty:
                    SkeletonCircle()
                @unknown default:
                    avatarFallback
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .allowsHitTesting(false)
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 44, height: 44)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}


/// Monochrome Patreon mark (circle + stem), inherits label tint.
private struct PatreonGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            // Circle
            let circleRect = CGRect(x: w * 0.08, y: h * 0.12, width: w * 0.58, height: h * 0.58)
            context.fill(Path(ellipseIn: circleRect), with: .foreground)
            // Stem
            let stem = CGRect(x: w * 0.62, y: h * 0.18, width: w * 0.22, height: h * 0.70)
            context.fill(Path(roundedRect: stem, cornerRadius: w * 0.08), with: .foreground)
        }
        .accessibilityHidden(true)
    }
}

/// Monochrome Boosty-style mark (rounded bolt), inherits label tint.
private struct BoostyGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.58, y: h * 0.05))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.95))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.42))
            path.closeSubpath()
            context.fill(path, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
