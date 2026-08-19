import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Shikimori

struct ShikimoriSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @State private var showImporter = false
    @State private var importResult: String?

    var body: some View {
        List {
            Section {
                Toggle("Блок Shikimori в карточке аниме", isOn: $appSettings.showShikimoriOnReleaseCard)
            }

            Section {
                if !ShikimoriConfig.isConfigured {
                    Text(ShikimoriConfig.configurationHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if shikimoriAuth.isAuthenticated, let profile = shikimoriAuth.profile {
                    HStack {
                        Label(profile.nickname, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button {
                            shikimoriAuth.disconnect()
                        } label: {
                            Label("Отключить", systemImage: "xmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
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
                Text("Аккаунт")
            }

            Section {
                ShareLink(item: shikimoriExportDocument, preview: SharePreview("Shikimori Links")) {
                    Label("Экспорт привязок", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)

                Button {
                    showImporter = true
                } label: {
                    Label("Импорт привязок", systemImage: "square.and.arrow.down")
                }

                if let importResult {
                    Text(importResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Данные")
            }
        }
        .navigationTitle("Shikimori")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await shikimoriAuth.restoreSession()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importLinks(from: url)
            case .failure(let error):
                importResult = error.localizedDescription
            }
        }
    }

    private var canExport: Bool {
        !ShikimoriLinkStore.shared.links.isEmpty
    }

    private var shikimoriExportDocument: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shikimori-links.json")
        do {
            let data = try ShikimoriLinkStore.shared.exportJSON()
            try data.write(to: url, options: .atomic)
        } catch {
            ToastCenter.shared.show("Не удалось подготовить экспорт", isError: true)
        }
        return url
    }

    private func importLinks(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let count = try ShikimoriLinkStore.shared.importJSON(data, merge: true)
            importResult = "Импортировано привязок: \(count)"
            ToastCenter.shared.show("Импортировано: \(count)")
        } catch {
            importResult = error.localizedDescription
            ToastCenter.shared.show(error.localizedDescription, isError: true)
        }
    }
}

// MARK: - Storage

struct StorageSettingsView: View {
    @State private var showConfirmation = false

    var body: some View {
        List {
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
                    showConfirmation = true
                }
            } footer: {
                Text("Скачанные серии очищаются во вкладке «Загрузки», не здесь.")
            }
        }
        .navigationTitle("Память и кеш")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Что очистить?",
            isPresented: $showConfirmation,
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
