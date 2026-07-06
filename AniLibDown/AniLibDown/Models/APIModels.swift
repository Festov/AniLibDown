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
    let value: String
    let description: String
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

struct Genre: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct EpisodeSkip: Codable, Hashable {
    let start: Int?
    let stop: Int?
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
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [Genre]?
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
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [Genre]?
    let latestEpisode: Episode
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
    let ageRating: ReleaseAgeRating?
    let description: String?
    let episodesTotal: Int?
    let genres: [Genre]?
    let episodes: [Episode]
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

struct UserProfile: Codable, Identifiable {
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

enum CollectionType: String, CaseIterable, Identifiable {
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

struct APIErrorResponse: Decodable {
    let message: String?
    let error: String?
}
