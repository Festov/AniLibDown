import XCTest
@testable import AniLibDown

final class ScheduleDecodingTests: XCTestCase {
    func testDecodeScheduleNow() throws {
        let json = """
        {
          "today": [{
            "release": {
              "id": 1,
              "year": 2026,
              "name": {"main": "Test", "english": null, "alternative": null},
              "alias": "test",
              "is_ongoing": true,
              "is_in_production": true,
              "publish_day": {"value": 4, "description": "Четверг"}
            },
            "full_season_is_released": false,
            "published_release_episode": null,
            "next_release_episode_number": 3
          }],
          "tomorrow": [],
          "yesterday": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let schedule = try decoder.decode(ScheduleNowResponse.self, from: json)

        XCTAssertEqual(schedule.today.count, 1)
        XCTAssertEqual(schedule.today[0].release.id, 1)
        XCTAssertEqual(schedule.today[0].release.publishDay?.value, 4)
        XCTAssertEqual(schedule.today[0].nextReleaseEpisodeNumber, 3)
        XCTAssertEqual(schedule.today[0].subtitle, "Следующая: 3")
    }

    func testPublishDayCalendarWeekday() {
        XCTAssertEqual(PublishDay(value: 1, description: "Понедельник").calendarWeekday, 2)
        XCTAssertEqual(PublishDay(value: 7, description: "Воскресенье").calendarWeekday, 1)
    }
}
