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
            if let friendly = Self.friendlyServerMessage(message, status: status) {
                return friendly
            }
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

    private static func friendlyServerMessage(_ message: String?, status: Int) -> String? {
        let lower = (message ?? "").lowercased()
        if status == 404
            || lower.contains("no query results for model")
            || lower.contains("not found") {
            return "Тайтл недоступен. Возможно, нужен VPN или релиз временно недоступен."
        }
        return nil
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

    func getCatalog(
        page: Int,
        limit: Int = 20,
        search: String? = nil,
        genreIds: [Int] = [],
        sorting: CatalogSorting = .freshAtDesc,
        year: Int? = nil
    ) async throws -> CatalogResponse {
        var query = [
            "page": String(page),
            "limit": String(limit),
            "f[sorting]": sorting.rawValue
        ]
        if let search, !search.isEmpty {
            query["f[search]"] = search
        }
        if !genreIds.isEmpty {
            query["f[genres]"] = genreIds.map(String.init).joined(separator: ",")
        }
        if let year {
            query["f[years][from_year]"] = String(year)
            query["f[years][to_year]"] = String(year)
        }
        return try await request(path: "anime/catalog/releases", query: query)
    }

    func getCatalogGenres() async throws -> [AnimeGenre] {
        try await request(path: "anime/catalog/references/genres")
    }

    func getRelease(idOrAlias: String) async throws -> ReleaseDetail {
        try await request(path: "anime/releases/\(idOrAlias)")
    }

    func getReleaseMembers(idOrAlias: String) async throws -> [ReleaseMember] {
        try await request(path: "anime/releases/\(idOrAlias)/members")
    }

    func getRandomReleases(limit: Int = 1) async throws -> [ReleaseSummary] {
        try await request(path: "anime/releases/random", query: ["limit": String(limit)])
    }

    func getFranchises(forReleaseId releaseId: Int) async throws -> [Franchise] {
        try await request(path: "anime/franchises/release/\(releaseId)")
    }

    func getScheduleNow() async throws -> ScheduleNowResponse {
        try await request(path: "anime/schedule/now")
    }

    func getScheduleWeek() async throws -> [ScheduleItem] {
        try await request(path: "anime/schedule/week")
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

    func getCollectionIds() async throws -> [CollectionMembership] {
        try await request(path: "accounts/users/me/collections/ids", authorized: true)
    }

    func addToCollection(releaseId: Int, type: CollectionType) async throws {
        try await requestVoid(
            path: "accounts/users/me/collections",
            method: "POST",
            body: [CollectionAddRequest(releaseId: releaseId, typeOfCollection: type.rawValue)],
            authorized: true
        )
    }

    func removeFromCollection(releaseId: Int) async throws {
        try await requestVoid(
            path: "accounts/users/me/collections",
            method: "DELETE",
            body: [CollectionRemoveRequest(releaseId: releaseId)],
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

        let data = try await performDataWithRetry(request: request, method: method)
        return data
    }

    private func performDataWithRetry(request: URLRequest, method: String) async throws -> Data {
        let maxAttempts = method == "GET" ? 3 : 1
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                AppLog.api.debug("Retry \(attempt)/\(maxAttempts - 1) for \(request.url?.absoluteString ?? "")")
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                let path = request.url?.path ?? ""
                if httpResponse.statusCode == 401, !path.contains("auth/login") {
                    throw APIError.unauthorized
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return data
                }

                let message = (try? decode(APIErrorResponse.self, from: data)).flatMap {
                    $0.message ?? $0.error
                }
                let error = APIError.httpError(status: httpResponse.statusCode, message: message)
                lastError = error
                guard isRetriable(error), attempt < maxAttempts - 1 else { throw error }
                // Сервер явно попросил подождать (429/503) — слушаемся, иначе backoff.
                let retryAfter = Self.retryAfterSeconds(from: httpResponse)
                try await Task.sleep(nanoseconds: Self.retryDelayNanos(attempt: attempt, retryAfter: retryAfter))
            } catch {
                // APIError сюда попадает только осознанным throw выше — просто пробрасываем.
                if error is APIError { throw error }
                lastError = error
                guard isRetriable(error), attempt < maxAttempts - 1 else { throw error }
                try await Task.sleep(nanoseconds: Self.retryDelayNanos(attempt: attempt, retryAfter: nil))
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    /// Задержка перед повтором: exponential backoff 1с → 2с → 4с…,
    /// либо значение Retry-After, если сервер его прислал (ограничено 30 секундами).
    static func retryDelayNanos(attempt: Int, retryAfter: TimeInterval?) -> UInt64 {
        let seconds = retryAfter ?? pow(2.0, Double(attempt))
        return UInt64(min(seconds, 30) * 1_000_000_000)
    }

    /// Парсит заголовок Retry-After: поддерживаются delta-секунды и HTTP-date.
    static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func isRetriable(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if case .httpError(let status, _) = apiError {
                return status >= 500 || status == 429
            }
            return false
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        return false
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

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
