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

                Section("Поддержать проект") {
                    Link(destination: URL(string: "https://www.patreon.com/aniliberty")!) {
                        Label("Patreon", systemImage: "heart.fill")
                    }
                    Link(destination: URL(string: "https://boosty.to/aniliberty")!) {
                        Label("Boosty", systemImage: "bolt.fill")
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

                Text("Смена аватара, пароля и почты пока доступна на сайте AniLiberty — в API приложения этих методов нет.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
