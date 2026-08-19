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

                aboutSection
            }
            .navigationTitle(L10n.profile)
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        if authService.isAuthenticated, let profile = authService.profile {
            Section {
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
                    }

                    Spacer(minLength: 0)
                }

                Button("Выйти", role: .destructive) {
                    Task { await authService.logout() }
                }
            }
        } else {
            Section {
                Button("Войти") {
                    showLogin = true
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: AppVersion.display)
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
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 44, height: 44)
            .foregroundStyle(.secondary)
    }
}
