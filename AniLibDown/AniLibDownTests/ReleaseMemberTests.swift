import XCTest
@testable import AniLibDown

final class ReleaseMemberTests: XCTestCase {
    func testDecodeMembersFromReleasePayload() throws {
        let json = """
        {
          "id": 1,
          "year": 2026,
          "name": { "main": "Test", "english": null, "alternative": null },
          "alias": "test",
          "is_ongoing": true,
          "episodes": [],
          "members": [
            {
              "id": "a",
              "role": { "value": "voicing", "description": "Озвучка" },
              "nickname": "JazzJack",
              "user": null
            },
            {
              "id": "b",
              "role": { "value": "decorating", "description": "Оформление" },
              "nickname": "Just Noname",
              "user": null
            },
            {
              "id": "c",
              "role": { "value": "voicing", "description": "Озвучка" },
              "nickname": "Abe",
              "user": null
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(ReleaseDetail.self, from: json)

        XCTAssertEqual(release.members.count, 3)
        let sections = ReleaseMemberRoleOrder.sections(from: release.members)
        XCTAssertEqual(sections.map(\.title), ["Озвучка", "Оформление"])
        XCTAssertEqual(sections[0].members.map(\.nickname), ["JazzJack", "Abe"])
    }
}
