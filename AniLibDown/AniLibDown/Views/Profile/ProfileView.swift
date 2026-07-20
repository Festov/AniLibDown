import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var playerSettings = PlayerSettings.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @State private var showLogin = false
    @State private var showCacheConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                playbackSection
                shikimoriSection
                storageSection
                aboutSection
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
                Text("Скачанные серии не удаляются. Можно очистить только выбранный тип кеша.")
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

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Тема", selection: $appSettings.colorSchemePreference) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Text(scheme.title).tag(scheme)
                }
            }

            Toggle("Заставка при запуске", isOn: $appSettings.isSplashEnabled)
        } header: {
            Text("Оформление")
        } footer: {
            Text("Тема меняет светлый/тёмный вид приложения. Заставка показывается при каждом запуске.")
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section {
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
        } header: {
            Text("Просмотр")
        } footer: {
            Text("Качество по умолчанию используется при старте серии. В плеере качество можно сменить отдельно. Ускорение срабатывает при удержании правой половины экрана.")
        }
    }

    // MARK: - Shikimori

    private var shikimoriSection: some View {
        Section {
            Toggle("Блок Shikimori в карточке аниме", isOn: $appSettings.showShikimoriOnReleaseCard)

            if !ShikimoriConfig.isConfigured {
                Text(ShikimoriConfig.configurationHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if shikimoriAuth.isAuthenticated, let profile = shikimoriAuth.profile {
                HStack {
                    Label(profile.nickname, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Отключить") {
                        shikimoriAuth.disconnect()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            } else {
                Button {
                    Task { await shikimoriAuth.connect() }
                } label: {
                    if shikimoriAuth.isLoading {
                        HStack {
                            ProgressView()
                            Text("Подключение…")
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
        } header: {
            Text("Shikimori")
        } footer: {
            Text("Позволяет ставить статус списка (смотрю, просмотрено и т.д.) из карточки аниме. Привязки хранятся только на телефоне и сбрасываются при переустановке.")
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            ForEach(AppCacheKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Button("Очистить кеш…", role: .destructive) {
                showCacheConfirmation = true
            }
        } header: {
            Text("Память и кеш")
        } footer: {
            Text("Скачанные серии очищаются во вкладке «Загрузки», не здесь.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: AppSettings.appVersion)
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
