import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var playerSettings = PlayerSettings.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @State private var showLogin = false
    @State private var showCacheConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if authService.isAuthenticated, let profile = authService.profile {
                    authenticatedContent(profile: profile)
                } else {
                    guestContent
                }
            }
            .navigationTitle("Профиль")
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .task {
                await shikimoriAuth.restoreSession()
            }
            .confirmationDialog(
                "Что очистить?",
                isPresented: $showCacheConfirmation,
                titleVisibility: .visible
            ) {
                ForEach(AppCacheKind.allCases) { kind in
                    Button(kind.title, role: .destructive) {
                        AppCacheManager.clear([kind])
                    }
                }
                Button("Очистить всё", role: .destructive) {
                    AppCacheManager.clearAll()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Загрузки серий не удаляются. Можно выбрать только нужный тип кеша.")
            }
        }
    }

    private var guestContent: some View {
        List {
            playbackSettingsSection

            Section {
                Toggle("Показывать Shikimori", isOn: $appSettings.showShikimoriOnReleaseCard)
            } header: {
                Text("Карточка аниме")
            } footer: {
                Text("Привязки Shikimori хранятся локально на телефоне. Если переустановить приложение, привязки слетят.")
            }

            shikimoriSection
            cacheSection
            aboutSection

            Section {
                ContentUnavailableView {
                    Label("Войдите в аккаунт", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Авторизация нужна для коллекций и синхронизации с AniLiberty")
                } actions: {
                    Button("Войти") {
                        showLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func authenticatedContent(profile: UserProfile) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    profileAvatar(for: profile)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.nickname)
                            .font(.headline)
                            .lineLimit(1)
                        if let login = profile.login, login != profile.nickname {
                            Text("@\(login)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Button("Выйти", role: .destructive) {
                        Task { await authService.logout() }
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 2)
            }

            Section("Оформление") {
                Picker("Тема", selection: $appSettings.colorSchemePreference) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.title).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Заставка при запуске", isOn: $appSettings.isSplashEnabled)
            }

            playbackSettingsSection

            Section {
                Toggle("Показывать Shikimori", isOn: $appSettings.showShikimoriOnReleaseCard)
            } header: {
                Text("Карточка аниме")
            } footer: {
                Text("Привязки Shikimori хранятся локально на телефоне. Если переустановить приложение, привязки слетят.")
            }

            shikimoriSection
            cacheSection
            aboutSection
        }
    }

    private var playbackSettingsSection: some View {
        Section("Просмотр и загрузки") {
            Picker("Качество по умолчанию", selection: $appSettings.defaultVideoQuality) {
                ForEach(VideoQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }

            Picker("Ускорение при удержании", selection: $playerSettings.holdSpeedRate) {
                ForEach(HoldSpeedRate.allCases) { rate in
                    Text(rate.title).tag(rate)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Версия \(AppSettings.appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .listRowBackground(Color.clear)
        }
    }

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
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 48, height: 48)
            .foregroundStyle(.secondary)
    }

    private var cacheSection: some View {
        Section("Память") {
            ForEach(AppCacheKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.subheadline)
                    Text(kind.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Очистить кеш…", role: .destructive) {
                showCacheConfirmation = true
            }
        }
    }

    private var shikimoriSection: some View {
        Section("Shikimori") {
            if !ShikimoriConfig.isConfigured {
                Text(ShikimoriConfig.configurationHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if shikimoriAuth.isAuthenticated, let profile = shikimoriAuth.profile {
                HStack {
                    Label(profile.nickname, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Отключить", role: .destructive) {
                        shikimoriAuth.disconnect()
                    }
                    .font(.subheadline)
                }

                Text("В карточке релиза можно привязать тайтл и ставить статусы: смотрю, просмотрено, брошено и др.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Отмечайте статус просмотра на Shikimori прямо из карточки аниме.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await shikimoriAuth.connect() }
                } label: {
                    if shikimoriAuth.isLoading {
                        HStack {
                            ProgressView()
                            Text("Подключение...")
                        }
                    } else {
                        Text("Подключить Shikimori")
                    }
                }
                .disabled(shikimoriAuth.isLoading)
            }

            if let error = shikimoriAuth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
