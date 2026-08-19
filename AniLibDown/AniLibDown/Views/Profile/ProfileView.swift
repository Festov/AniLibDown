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
                } header: {
                    Text("Настройки")
                }

                Section {
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
                } header: {
                    Text("Данные")
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
                HStack(spacing: 14) {
                    profileAvatar(for: profile)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.nickname)
                            .font(.headline)
                            .lineLimit(1)
                        if let login = profile.login, login != profile.nickname {
                            Text("@\(login)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("AniLiberty")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 4)

                Button("Выйти из аккаунта", role: .destructive) {
                    Task { await authService.logout() }
                }
            } header: {
                Text("Аккаунт AniLiberty")
            } footer: {
                Text("Нужен для коллекций и синхронизации списков с сайтом.")
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Вы не вошли в аккаунт", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.headline)

                    Text("Войдите, чтобы пользоваться коллекциями AniLiberty на этом устройстве.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Войти") {
                        showLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Аккаунт AniLiberty")
            }
        }
    }



    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: AppVersion.display)
        } header: {
            Text("О приложении")
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
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 56, height: 56)
            .foregroundStyle(.secondary)
    }
}
