import Foundation

enum APIConfig {
    static let baseURL = URL(string: "https://aniliberty.top/api/v1")!
    static let mediaBaseURL = URL(string: "https://aniliberty.top")!
    static let userAgent = "AniLibDown/1.0.2 (iOS)"

    static func mediaURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("file:") {
            return URL(string: path)
        }
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        return URL(string: path, relativeTo: mediaBaseURL)?.absoluteURL
    }
}
