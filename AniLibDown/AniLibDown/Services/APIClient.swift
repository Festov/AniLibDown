import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case httpError(status: Int, message: String?)
    case decodingError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный URL"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .emptyResponse:
            return "Сервер вернул пустой ответ"
        case .httpError(let status, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Ошибка сервера (\(status))"
        case .decodingError(let error):
            if let decodingError = error as? DecodingError {
                return "Ошибка разбора данных: \(Self.describe(decodingError))"
            }
            return "Ошибка разбора данных: \(error.localizedDescription)"
        case .unauthorized:
            return "Требуется авторизация"
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "отсутствует поле \(key.stringValue)"
        case .valueNotFound(let type, let context):
            return "пустое значение \(type) в \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "неверный тип \(type) в \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var accessToken: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": APIConfig.userAgent]
        session = URLSession(configuration: config)
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: Encodable? = nil,
        authorized: Bool = false
    ) async throws -> T {
        let data = try await performRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            authorized: authorized
        )
        return try decode(T.self, from: data)
    }

    func requestVoid(
        path: String,
        method: String = "POST",
        body: Encodable? = nil,
        authorized: Bool = false
    ) async throws {
        _ = try await performRequest(
            path: path,
            method: method,
            body: body,
            authorized: authorized
        )
    }

    // MARK: - Public API

    func login(login: String, password: String) async throws -> String {
        let data = try await performRequest(
            path: "accounts/users/auth/login",
            method: "POST",
            body: LoginRequest(login: login, password: password)
        )

        let response = try decode(LoginResponse.self, from: data)
        guard let token = response.token, !token.isEmpty else {
            throw APIError.httpError(
                status: 401,
                message: response.error ?? "Неверный логин или пароль"
            )
        }
        accessToken = token
        return token
    }

    func logout() async throws {
        try await requestVoid(path: "accounts/users/auth/logout", method: "POST", authorized: true)
        accessToken = nil
    }

    func getProfile() async throws -> UserProfile {
        try await request(path: "accounts/users/me/profile", authorized: true)
    }

    func getLatestReleases(limit: Int = 20) async throws -> [ReleaseLatest] {
        try await request(path: "anime/releases/latest", query: ["limit": String(limit)])
    }

    func getCatalog(page: Int, limit: Int = 20, search: String? = nil) async throws -> CatalogResponse {
        var query = [
            "page": String(page),
            "limit": String(limit),
            "f[sorting]": "FRESH_AT_DESC"
        ]
        if let search, !search.isEmpty {
            query["f[search]"] = search
        }
        return try await request(path: "anime/catalog/releases", query: query)
    }

    func getRelease(idOrAlias: String) async throws -> ReleaseDetail {
        try await request(path: "anime/releases/\(idOrAlias)")
    }

    func getCollection(type: CollectionType, page: Int, limit: Int = 20) async throws -> CollectionResponse {
        try await request(
            path: "accounts/users/me/collections/releases",
            query: [
                "type_of_collection": type.rawValue,
                "page": String(page),
                "limit": String(limit)
            ],
            authorized: true
        )
    }

    // MARK: - Private

    private func performRequest(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: Encodable? = nil,
        authorized: Bool = false
    ) async throws -> Data {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if authorized, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401, path != "accounts/users/auth/login" {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? decode(APIErrorResponse.self, from: data)).flatMap {
                $0.message ?? $0.error
            }
            throw APIError.httpError(status: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else {
            throw APIError.emptyResponse
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
