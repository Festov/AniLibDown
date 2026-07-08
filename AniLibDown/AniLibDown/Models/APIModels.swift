import Foundation

// MARK: - Common

struct PaginatedMeta: Decodable {
    let pagination: Pagination
}

struct Pagination: Decodable {
    let total: Int
    let count: Int
    let perPage: Int
    let currentPage: Int
    let totalPages: Int
}

struct ImageAsset: Codable, Hashable {
    let src: String?
    let preview: String?
    let thumbnail: String?
    let optimized: OptimizedImage?

    var displayURL: String? {
        optimized?.preview ?? preview ?? src ?? thumbnail
    }
}

struct OptimizedImage: Codable, Hashable {
    let src: String?
    let preview: String?
    let thumbnail: String?
}

struct LabeledValue: Codable, Hashable {
    let value: String?
    let description: String?
}

struct ReleaseName: Codable, Hashable {
    let main: String
    let english: String?
    let alternative: String?
}

struct ReleaseAgeRating: Codable, Hashable {
    let value: String
    let label: String
    let isAdult: Bool
    let description: String?
}

struct AnimeGenre: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct EpisodeSkip: Codable, Hashable {
    let start: Int?
    let stop: Int?
}

enum BroadcastStatus: String {
    case ongoing
    case released
    case upcoming

    var title: String {
        switch self {
        case .ongoing: return "Онгоинг"
        case .released: return "Вышло"
        case .upcoming: return "Не вышло"
        }
    }
}

enum ReleaseFormatting {
    static func yearString(_ year: Int) -> String {
        String(year)
    }

    static func broadcastStatus(
        isOngoing: Bool,
        isInProduction: Bool,
        episodesCount: Int,
        episodesTotal: Int?
    ) -> BroadcastStatus {
        if isOngoing { return .ongoing }
        let knownEpisodes = max(episodesCount, episodesTotal ?? 0)
        if knownEpisodes > 0 { return .released }
        if isInProduction { return .released }
        return .upcoming
    }
}

extension ReleaseSummary {
    var broadcastStatus: BroadcastStatus {
        ReleaseFormatting.broadcastStatus(
            isOngoing: isOngoing,
            isInProduction: isInProduction,
            episodesCount: episodesTotal ?? 0,
            episodesTotal: episodesTotal
        )
    }
}

extension ReleaseLatest {
    var broadcastStatus: BroadcastStatus {
        ReleaseFormatting.broadcastStatus(
            isOngoing: isOngoing,
            isInProduction: isInProduction,
            episodesCount: max(episodesTotal ?? 0, Int(latestEpisode.ordinal)),
            episodesTotal: episodesTotal
        )
    }
}

extension ReleaseDetail {
    var broadcastStatus: BroadcastStatus {
        ReleaseFormatting.broadcastStatus(
            isOngoing: isOngoing,
            isInProduction: isInProduction,
            episodesCount: episodes.count,
            episodesTotal: episodesTotal
        )
    }
}

// MARK: - Release

struct ReleaseSummary: Codable, Identifiable, Hashable {
    let id: Int
    let type: LabeledValue?
    let year: Int
    let name: ReleaseName
    let alias: String
    let season: LabeledValue?
    let poster: ImageAsset?
    let isOngoing: Bool
    let isInProduction: Bool
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [AnimeGenre]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decodeIfPresent(LabeledValue.self, forKey: .type)
        year = try container.decode(Int.self, forKey: .year)
        name = try container.decode(ReleaseName.self, forKey: .name)
        alias = try container.decode(String.self, forKey: .alias)
        season = try container.decodeIfPresent(LabeledValue.self, forKey: .season)
        poster = try container.decodeIfPresent(ImageAsset.self, forKey: .poster)
        isOngoing = try container.decode(Bool.self, forKey: .isOngoing)
        isInProduction = try container.decodeIfPresent(Bool.self, forKey: .isInProduction) ?? false
        ageRating = try container.decodeIfPresent(ReleaseAgeRating.self, forKey: .ageRating)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        episodesTotal = try container.decodeIfPresent(Int.self, forKey: .episodesTotal)
        genres = try container.decodeIfPresent([AnimeGenre].self, forKey: .genres)
    }
}

struct ReleaseLatest: Codable, Identifiable, Hashable {
    let id: Int
    let type: LabeledValue?
    let year: Int
    let name: ReleaseName
    let alias: String
    let season: LabeledValue?
    let poster: ImageAsset?
    let isOngoing: Bool
    let isInProduction: Bool
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [AnimeGenre]?
    let latestEpisode: Episode

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decodeIfPresent(LabeledValue.self, forKey: .type)
        year = try container.decode(Int.self, forKey: .year)
        name = try container.decode(ReleaseName.self, forKey: .name)
        alias = try container.decode(String.self, forKey: .alias)
        season = try container.decodeIfPresent(LabeledValue.self, forKey: .season)
        poster = try container.decodeIfPresent(ImageAsset.self, forKey: .poster)
        isOngoing = try container.decode(Bool.self, forKey: .isOngoing)
        isInProduction = try container.decodeIfPresent(Bool.self, forKey: .isInProduction) ?? false
        ageRating = try container.decodeIfPresent(ReleaseAgeRating.self, forKey: .ageRating)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        episodesTotal = try container.decodeIfPresent(Int.self, forKey: .episodesTotal)
        genres = try container.decodeIfPresent([AnimeGenre].self, forKey: .genres)
        latestEpisode = try container.decode(Episode.self, forKey: .latestEpisode)
    }
}

struct ReleaseDetail: Codable, Identifiable {
    let id: Int
    let type: LabeledValue?
    let year: Int
    let name: ReleaseName
    let alias: String
    let season: LabeledValue?
    let poster: ImageAsset?
    let isOngoing: Bool
    let isInProduction: Bool
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [AnimeGenre]?
    let episodes: [Episode]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decodeIfPresent(LabeledValue.self, forKey: .type)
        year = try container.decode(Int.self, forKey: .year)
        name = try container.decode(ReleaseName.self, forKey: .name)
        alias = try container.decode(String.self, forKey: .alias)
        season = try container.decodeIfPresent(LabeledValue.self, forKey: .season)
        poster = try container.decodeIfPresent(ImageAsset.self, forKey: .poster)
        isOngoing = try container.decode(Bool.self, forKey: .isOngoing)
        isInProduction = try container.decodeIfPresent(Bool.self, forKey: .isInProduction) ?? false
        ageRating = try container.decodeIfPresent(ReleaseAgeRating.self, forKey: .ageRating)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        episodesTotal = try container.decodeIfPresent(Int.self, forKey: .episodesTotal)
        genres = try container.decodeIfPresent([AnimeGenre].self, forKey: .genres)
        episodes = try container.decode([Episode].self, forKey: .episodes)
    }
}

// MARK: - Episode

struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let ordinal: Double
    let opening: EpisodeSkip?
    let ending: EpisodeSkip?
    let preview: ImageAsset?
    let hls480: String?
    let hls720: String?
    let hls1080: String?
    let duration: Int?
    let releaseId: Int?

    var bestStreamURL: URL? {
        [hls1080, hls720, hls480]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    var displayTitle: String {
        if let name, !name.isEmpty {
            return "Серия \(ordinalFormatted): \(name)"
        }
        return "Серия \(ordinalFormatted)"
    }

    var playerEpisodeTitle: String {
        if let name, !name.isEmpty { return name }
        return "Серия \(ordinalFormatted)"
    }

    var ordinalFormatted: String {
        ordinal.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", ordinal)
            : String(ordinal)
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }

    func streamURL(for episode: Episode) -> URL? {
        let urlString: String?
        switch self {
        case .p1080: urlString = episode.hls1080
        case .p720: urlString = episode.hls720
        case .p480: urlString = episode.hls480
        }
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}

// MARK: - Auth

struct LoginRequest: Encodable {
    let login: String
    let password: String
}

struct LoginResponse: Decodable {
    let token: String?
    let error: String?
}

struct UserProfile: Decodable, Identifiable {
    let id: Int
    let login: String?
    let email: String?
    let nickname: String
    let avatar: ImageAsset?
    let isBanned: Bool
    let isWithAds: Bool
    let createdAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        login = try container.decodeIfPresent(String.self, forKey: .login)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? login ?? "Пользователь"
        avatar = try container.decodeIfPresent(ImageAsset.self, forKey: .avatar)
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        isWithAds = try container.decodeIfPresent(Bool.self, forKey: .isWithAds) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, login, email, nickname, avatar, createdAt, isBanned, isWithAds
    }
}

enum CollectionType: String, CaseIterable, Identifiable, Hashable {
    case watching = "WATCHING"
    case planned = "PLANNED"
    case watched = "WATCHED"
    case postponed = "POSTPONED"
    case abandoned = "ABANDONED"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watching: return "Смотрю"
        case .planned: return "Запланировано"
        case .watched: return "Просмотрено"
        case .postponed: return "Отложено"
        case .abandoned: return "Брошено"
        }
    }
}

// MARK: - Responses

struct CatalogResponse: Decodable {
    let data: [ReleaseSummary]
    let meta: PaginatedMeta
}

struct CollectionResponse: Decodable {
    let data: [ReleaseSummary]
    let meta: PaginatedMeta
}

struct CollectionAddRequest: Encodable {
    let releaseId: Int
    let typeOfCollection: String

    enum CodingKeys: String, CodingKey {
        case releaseId = "release_id"
        case typeOfCollection = "type_of_collection"
    }
}

struct CollectionRemoveRequest: Encodable {
    let releaseId: Int

    enum CodingKeys: String, CodingKey {
        case releaseId = "release_id"
    }
}

struct CollectionMembership: Decodable {
    let releaseId: Int
    let type: CollectionType

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        releaseId = try container.decode(Int.self)
        let rawType = try container.decode(String.self)
        guard let collectionType = CollectionType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown collection type: \(rawType)"
            )
        }
        type = collectionType
    }
}

struct PlayerSession: Identifiable {
    let id = UUID()
    let releaseId: Int
    let releaseTitle: String
    let episodes: [Episode]
    let startEpisodeId: String
    let quality: VideoQuality
    let preferOffline: Bool
    let episodesTotal: Int?

    var startIndex: Int {
        episodes.firstIndex(where: { $0.id == startEpisodeId }) ?? 0
    }

    var totalEpisodes: Int {
        episodesTotal ?? episodes.count
    }
}

struct DownloadReleaseGroup: Identifiable {
    let id: String
    let releaseId: Int?
    let releaseTitle: String
    let items: [DownloadItem]

    var completedCount: Int {
        items.filter { $0.state == .completed }.count
    }

    var activeCount: Int {
        items.filter { $0.state == .downloading || $0.state == .queued }.count
    }
}

struct APIErrorResponse: Decodable {
    let message: String?
    let error: String?
}

