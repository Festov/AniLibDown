import Foundation

enum ShikimoriListStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case planned
    case watching
    case completed
    case on_hold
    case dropped
    case rewatching

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: return "Запланировано"
        case .watching: return "Смотрю"
        case .completed: return "Просмотрено"
        case .on_hold: return "Отложено"
        case .dropped: return "Брошено"
        case .rewatching: return "Пересматриваю"
        }
    }
}

struct ShikimoriUserProfile: Codable {
    let id: Int
    let nickname: String
}

struct ShikimoriImage: Codable {
    let preview: String?
    let original: String?
}

struct ShikimoriAnime: Codable, Identifiable {
    let id: Int
    let name: String
    let russian: String?
    let image: ShikimoriImage?
    let kind: String?
    let year: Int?

    var displayTitle: String {
        if let russian, !russian.isEmpty {
            return russian
        }
        return name
    }

    var previewURL: URL? {
        guard let path = image?.preview ?? image?.original else { return nil }
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        return URL(string: path, relativeTo: ShikimoriConfig.baseURL)?.absoluteURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, russian, image, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        russian = try container.decodeIfPresent(String.self, forKey: .russian)
        image = try container.decodeIfPresent(ShikimoriImage.self, forKey: .image)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        year = nil
    }
}

struct ShikimoriUserRate: Codable, Identifiable {
    let id: Int
    let userId: Int
    let targetId: Int
    let targetType: String
    let status: String
    let episodes: Int?

    var listStatus: ShikimoriListStatus? {
        ShikimoriListStatus(rawValue: status)
    }
}

struct ShikimoriLink: Codable, Hashable {
    let animeId: Int
    let title: String
}

struct ShikimoriTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct ShikimoriUserRatePayload: Encodable {
    let userRate: ShikimoriUserRateBody

    enum CodingKeys: String, CodingKey {
        case userRate = "user_rate"
    }
}

struct ShikimoriUserRateBody: Encodable {
    let userId: Int
    let targetId: Int
    let targetType: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case targetId = "target_id"
        case targetType = "target_type"
        case status
    }
}

struct ShikimoriUserRateUpdatePayload: Encodable {
    let userRate: ShikimoriUserRateUpdateBody

    enum CodingKeys: String, CodingKey {
        case userRate = "user_rate"
    }
}

struct ShikimoriUserRateUpdateBody: Encodable {
    let status: String?
    let episodes: Int?

    init(status: String? = nil, episodes: Int? = nil) {
        self.status = status
        self.episodes = episodes
    }
}

enum ShikimoriError: LocalizedError, Equatable {
    case notConfigured
    case notAuthenticated
    case authorizationCancelled
    case invalidCallback
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return ShikimoriConfig.configurationHint
        case .notAuthenticated:
            return "Подключите аккаунт Shikimori в профиле"
        case .authorizationCancelled:
            return "Авторизация отменена"
        case .invalidCallback:
            return "Не удалось получить код авторизации"
        case .apiError(let message):
            return message
        }
    }
}
