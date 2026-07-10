import SwiftUI

@MainActor
final class CollectionViewModel: ObservableObject {
    @Published var releases: [ReleaseSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(type: CollectionType) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.getCollection(type: type, page: 1, limit: 50)
            releases = response.data
        } catch {
            errorMessage = error.localizedDescription
            releases = []
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @StateObject private var collectionViewModel = CollectionViewModel()
    @State private var showLogin = false
    @State private var selectedCollection: CollectionType = .watching

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
        }
    }

    private var guestContent: some View {
        List {
            shikimoriSection

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

            shikimoriSection

            Section("Моя коллекция") {
                Picker("Тип", selection: $selectedCollection) {
                    ForEach(CollectionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedCollection) { _, newValue in
                    Task { await collectionViewModel.load(type: newValue) }
                }

                if collectionViewModel.isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        ReleaseRowSkeletonView()
                    }
                } else if let error = collectionViewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if collectionViewModel.releases.isEmpty {
                    Text("Коллекция пуста")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(collectionViewModel.releases) { release in
                        NavigationLink(value: release.id) {
                            ReleaseRowView(
                                title: release.name.main,
                                subtitle: ReleaseFormatting.yearString(release.year),
                                posterPath: release.poster?.displayURL,
                                status: release.broadcastStatus
                            )
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Int.self) { releaseId in
            ReleaseDetailView(releaseId: releaseId)
        }
        .task(id: selectedCollection) {
            await collectionViewModel.load(type: selectedCollection)
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
