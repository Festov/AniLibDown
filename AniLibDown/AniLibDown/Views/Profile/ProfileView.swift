import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService

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

                Section {
                    Text(AppVersion.profileLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(L10n.profile)
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        if let profile = authService.profile {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                    Button("Выйти", role: .destructive) {
                        Task { await authService.logout() }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
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
