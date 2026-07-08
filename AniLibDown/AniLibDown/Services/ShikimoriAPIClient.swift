import Foundation

actor ShikimoriAPIClient {
    static let shared = ShikimoriAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": ShikimoriConfig.userAgent]
        session = URLSession(configuration: config)
    }

    func whoami(accessToken: String) async throws -> ShikimoriUserProfile {
        try await authorizedRequest(
            path: "/api/users/whoami",
            method: "GET",
            accessToken: accessToken
        )
    }

    func searchAnimes(query: String, limit: Int = 20) async throws -> [ShikimoriAnime] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/api/animes?search=\(encoded)&limit=\(limit)&order=popularity"
        return try await publicRequest(path: path)
    }

    func userRate(
        userId: Int,
        animeId: Int,
        accessToken: String
    ) async throws -> ShikimoriUserRate? {
        let path = "/api/v2/user_rates?user_id=\(userId)&target_id=\(animeId)&target_type=Anime"
        let rates: [ShikimoriUserRate] = try await authorizedRequest(
            path: path,
            method: "GET",
            accessToken: accessToken
        )
        return rates.first
    }

    func createUserRate(
        userId: Int,
        animeId: Int,
        status: ShikimoriListStatus,
        accessToken: String
    ) async throws -> ShikimoriUserRate {
        let payload = ShikimoriUserRatePayload(
            userRate: ShikimoriUserRateBody(
                userId: userId,
                targetId: animeId,
                targetType: "Anime",
                status: status.rawValue
            )
        )
        return try await authorizedRequest(
            path: "/api/v2/user_rates",
            method: "POST",
            accessToken: accessToken,
            body: payload
        )
    }

    func updateUserRate(
        rateId: Int,
        status: ShikimoriListStatus,
        accessToken: String
    ) async throws -> ShikimoriUserRate {
        let payload = ShikimoriUserRateUpdatePayload(
            userRate: ShikimoriUserRateUpdateBody(status: status.rawValue)
        )
        return try await authorizedRequest(
            path: "/api/v2/user_rates/\(rateId)",
            method: "PATCH",
            accessToken: accessToken,
            body: payload
        )
    }

    func exchangeAuthorizationCode(_ code: String) async throws -> ShikimoriTokenResponse {
        try await tokenRequest(fields: [
            ("grant_type", "authorization_code"),
            ("client_id", ShikimoriConfig.clientId),
            ("client_secret", ShikimoriConfig.clientSecret),
            ("code", code),
            ("redirect_uri", ShikimoriConfig.redirectURI)
        ])
    }

    func refreshTokens(refreshToken: String) async throws -> ShikimoriTokenResponse {
        try await tokenRequest(fields: [
            ("grant_type", "refresh_token"),
            ("client_id", ShikimoriConfig.clientId),
            ("client_secret", ShikimoriConfig.clientSecret),
            ("refresh_token", refreshToken)
        ])
    }

    private func publicRequest<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: ShikimoriConfig.baseURL) else {
            throw ShikimoriError.apiError("Некорректный URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(ShikimoriConfig.userAgent, forHTTPHeaderField: "User-Agent")
        return try await perform(request)
    }

    private func authorizedRequest<T: Decodable>(
        path: String,
        method: String,
        accessToken: String
    ) async throws -> T {
        try await authorizedRequest(
            path: path,
            method: method,
            accessToken: accessToken,
            body: Optional<EmptyRequestBody>.none
        )
    }

    private func authorizedRequest<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        body: B?
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: ShikimoriConfig.baseURL) else {
            throw ShikimoriError.apiError("Некорректный URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(ShikimoriConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return try await perform(request)
    }

    private func tokenRequest(fields: [(String, String)]) async throws -> ShikimoriTokenResponse {
        guard let url = URL(string: "/oauth/token", relativeTo: ShikimoriConfig.baseURL) else {
            throw ShikimoriError.apiError("Некорректный URL")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(ShikimoriConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(fields: fields, boundary: boundary)

        return try await perform(request)
    }

    private func multipartBody(fields: [(String, String)], boundary: String) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShikimoriError.apiError("Некорректный ответ сервера")
        }

        if http.statusCode == 401 {
            throw ShikimoriError.notAuthenticated
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw ShikimoriError.apiError(message?.isEmpty == false ? message! : "Ошибка Shikimori (\(http.statusCode))")
        }

        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ShikimoriError.apiError("Ошибка разбора ответа: \(error.localizedDescription)")
        }
    }
}

private struct EmptyResponse: Decodable {
    init() {}
}

private struct EmptyRequestBody: Encodable {}
