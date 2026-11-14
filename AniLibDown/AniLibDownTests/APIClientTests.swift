import XCTest
@testable import AniLibDown

final class APIErrorTests: XCTestCase {
    func testFriendly404Message() {
        let error = APIError.httpError(status: 404, message: "No query results for model")
        XCTAssertTrue(error.localizedDescription.contains("VPN") || error.localizedDescription.contains("недоступен"))
    }
}

final class CatalogSortingTests: XCTestCase {
    func testSortingCases() {
        XCTAssertEqual(CatalogSorting.allCases.count, 3)
        XCTAssertEqual(CatalogSorting.freshAtDesc.title, "Сначала новые")
    }
}

final class APIRetryPolicyTests: XCTestCase {
    private func response(status: Int, retryAfter: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        return HTTPURLResponse(
            url: URL(string: "https://api.aniliberty.top/test")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    func testExponentialBackoff() {
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 0, retryAfter: nil), 1_000_000_000)
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 1, retryAfter: nil), 2_000_000_000)
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 2, retryAfter: nil), 4_000_000_000)
    }

    func testRetryAfterOverridesBackoff() {
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 0, retryAfter: 5), 5_000_000_000)
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 2, retryAfter: 7), 7_000_000_000)
    }

    func testRetryAfterIsCapped() {
        XCTAssertEqual(APIClient.retryDelayNanos(attempt: 0, retryAfter: 120), 30_000_000_000)
    }

    func testParsesDeltaSeconds() {
        XCTAssertEqual(APIClient.retryAfterSeconds(from: response(status: 429, retryAfter: "3")), 3)
        XCTAssertEqual(APIClient.retryAfterSeconds(from: response(status: 503, retryAfter: "0")), 0)
    }

    func testParsesHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let future = APIClient.retryAfterSeconds(
            from: response(status: 429, retryAfter: formatter.string(from: Date().addingTimeInterval(10)))
        )
        XCTAssertNotNil(future)
        XCTAssertGreaterThan(future!, 0)
        XCTAssertLessThanOrEqual(future!, 10)

        let past = APIClient.retryAfterSeconds(
            from: response(status: 429, retryAfter: formatter.string(from: Date().addingTimeInterval(-10)))
        )
        XCTAssertEqual(past, 0)
    }

    func testMissingOrGarbageRetryAfter() {
        XCTAssertNil(APIClient.retryAfterSeconds(from: response(status: 429, retryAfter: nil)))
        XCTAssertNil(APIClient.retryAfterSeconds(from: response(status: 429, retryAfter: "")))
        XCTAssertNil(APIClient.retryAfterSeconds(from: response(status: 429, retryAfter: "soon™")))
        XCTAssertNil(APIClient.retryAfterSeconds(from: response(status: 429, retryAfter: "-5")))
    }
}
