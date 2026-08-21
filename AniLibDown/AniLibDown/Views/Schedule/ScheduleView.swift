import SwiftUI

struct ScheduleView: View {
    @ObservedObject private var store = ScheduleStore.shared
    @ObservedObject private var alerts = EpisodeAlertStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.isLoading && store.nearSchedule == nil && store.weekItems.isEmpty {
                    ProgressView("Загрузка расписания…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.nearSchedule == nil && store.weekItems.isEmpty {
                    ContentUnavailableView {
                        Label("Нет расписания", systemImage: "calendar")
                    } description: {
                        Text(store.errorMessage ?? "Не удалось загрузить расписание")
                    } actions: {
                        Button("Повторить") {
                            Task { await store.load(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    scheduleList
                }
            }
            .navigationTitle(L10n.schedule)
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Вид", selection: $store.mode) {
                            ForEach(ScheduleStore.Mode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        Toggle("Только подписки", isOn: $store.showSubscribedOnly)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Фильтры расписания")
                }
            }
            .refreshable {
                await store.refresh()
            }
            .overlay {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .task {
                await store.loadIfNeeded()
            }
            .safeAreaInset(edge: .bottom) {
                if !appSettings.episodeNotificationsEnabled {
                    notificationsHint
                }
            }
        }
    }

    @ViewBuilder
    private var scheduleList: some View {
        List {
            switch store.mode {
            case .near:
                if let near = store.nearSchedule {
                    nearSection(title: "Сегодня", items: near.today)
                    nearSection(title: "Завтра", items: near.tomorrow)
                    nearSection(title: "Вчера", items: near.yesterday)
                }
            case .week:
                ForEach(store.weekSections, id: \.day.value) { section in
                    nearSection(title: section.day.description, items: section.items)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func nearSection(title: String, items: [ScheduleItem]) -> some View {
        let filtered = filteredItems(items)
        if !filtered.isEmpty {
            Section(title) {
                ForEach(filtered) { item in
                    HStack(spacing: 10) {
                        NavigationLink(value: item.release.id) {
                            ReleaseRowView(
                                title: item.release.name.main,
                                subtitle: item.subtitle,
                                posterPath: item.release.poster?.displayURL,
                                isOngoing: item.release.isOngoing
                            )
                        }
                        subscriptionButton(for: item)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
            }
        }
    }

    private func filteredItems(_ items: [ScheduleItem]) -> [ScheduleItem] {
        guard store.showSubscribedOnly else { return items }
        return items.filter { alerts.isSubscribed(releaseId: $0.release.id) }
    }

    private func subscriptionButton(for item: ScheduleItem) -> some View {
        let subscribed = alerts.isSubscribed(releaseId: item.release.id)
        return Button {
            alerts.toggleSubscription(for: item)
            if !subscribed, !appSettings.episodeNotificationsEnabled {
                appSettings.episodeNotificationsEnabled = true
                Task {
                    await NotificationManager.shared.requestAuthorizationIfNeeded()
                }
            }
        } label: {
            Image(systemName: subscribed ? "bell.fill" : "bell")
                .font(.body)
                .foregroundStyle(subscribed ? Color.accentColor : .secondary)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subscribed ? "Отключить уведомления" : "Включить уведомления")
    }

    private var notificationsHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
            Text("Нажмите на колокольчик, чтобы получать напоминания о сериях")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
