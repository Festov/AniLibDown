import SwiftUI

// MARK: - Notifications

struct NotificationsSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var episodeAlerts = EpisodeAlertStore.shared

    var body: some View {
        List {
            Section {
                Toggle("Уведомления о сериях", isOn: $appSettings.episodeNotificationsEnabled)
                    .onChange(of: appSettings.episodeNotificationsEnabled) { _, enabled in
                        if enabled {
                            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
                        }
                    }
            } footer: {
                Text("Уведомления приходят при выходе новых серий для подписанных релизов.")
            }

            if !episodeAlerts.subscriptions.isEmpty {
                Section("Подписки") {
                    ForEach(episodeAlerts.subscriptions) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let day = entry.publishDayTitle {
                                    Text(day)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Убрать") {
                                episodeAlerts.unsubscribe(releaseId: entry.releaseId)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Playback

struct PlaybackSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var playerSettings = PlayerSettings.shared

    var body: some View {
        List {
            Section {
                Picker("Качество по умолчанию", selection: $appSettings.defaultVideoQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
            } footer: {
                Text("Качество используется при старте серии. В плеере можно сменить отдельно.")
            }

            Section {
                Picker("Перемотка", selection: $playerSettings.seekInterval) {
                    ForEach(SeekInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }

                Picker("Ускорение при удержании", selection: $playerSettings.holdSpeedRate) {
                    ForEach(HoldSpeedRate.allCases) { rate in
                        Text(rate.title).tag(rate)
                    }
                }

                Toggle("Пропускать OP/ED", isOn: $playerSettings.skipOPED)

                Toggle("Автовоспроизведение следующей серии", isOn: $playerSettings.autoPlayNext)
            } header: {
                Text("Плеер")
            } footer: {
                Text("Ускорение срабатывает при удержании правой половины экрана.")
            }
        }
        .navigationTitle("Просмотр")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        List {
            Section {
                Picker("Тема", selection: $appSettings.colorSchemePreference) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.title).tag(scheme)
                    }
                }

                Toggle("Заставка при запуске", isOn: $appSettings.isSplashEnabled)
            } footer: {
                Text("Тема меняет светлый/тёмный вид приложения. Заставка показывается при каждом запуске.")
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Downloads

struct DownloadsSettingsView: View {
    @ObservedObject private var downloadSettings = DownloadSettings.shared

    var body: some View {
        List {
            Section {
                Toggle("Загрузки только по Wi‑Fi", isOn: $downloadSettings.wifiOnlyDownloads)

                Picker("Параллельные загрузки", selection: $downloadSettings.maxConcurrentDownloads) {
                    ForEach(DownloadSettings.concurrentOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            } footer: {
                Text("При подключении к Wi‑Fi очередь загрузок продолжится автоматически.")
            }
        }
        .navigationTitle("Загрузки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Collection Settings

struct CollectionSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        List {
            Section {
                ForEach(CollectionType.allCases) { type in
                    Toggle(type.title, isOn: Binding(
                        get: { !appSettings.hiddenCollectionTypes.contains(type) },
                        set: { visible in
                            if visible {
                                appSettings.hiddenCollectionTypes.remove(type)
                            } else {
                                appSettings.hiddenCollectionTypes.insert(type)
                            }
                        }
                    ))
                }
            } header: {
                Text("Видимые категории")
            } footer: {
                Text("Скрытые категории не будут отображаться в коллекции.")
            }
        }
        .navigationTitle("Коллекция")
        .navigationBarTitleDisplayMode(.inline)
    }
}
