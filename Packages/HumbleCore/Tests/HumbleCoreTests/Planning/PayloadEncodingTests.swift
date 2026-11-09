import Foundation
import Testing
@testable import HumbleCore

/// `PayloadEncodingTest` for the task requests (tests 32–34, 36): the server refuses a null for some fields
/// (Zod `.optional()` without `.nullable()`) and treats a missing key as "keep".
@Suite struct PayloadEncodingTests {
    private let payload = TaskPayload(projectId: "p", userIds: ["u"], statusId: "s", startDate: "2026-11-05")

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    @Test func clearedFieldsGoOutAsNull() throws {
        let object = try json(payload)
        for key in ["endDate", "startTime", "endTime", "link", "placeId", "placeText", "resourceId"] {
            #expect(object[key] is NSNull, "\(key)")
        }
        #expect(object["isMilestone"] as? Bool == false)
        #expect(object["title"] as? String == "" && object["notes"] as? String == "")
    }

    @Test func lockIsLeftOutWithoutTheRight() throws {
        #expect(try json(payload)["isLocked"] == nil)
    }

    @Test func lockGoesOutWithTheRight() throws {
        var locked = payload
        locked.isLocked = false
        #expect(try json(locked)["isLocked"] as? Bool == false)
    }

    @Test func coordinatesAreLeftOutWhenTheAddressDidNotChange() throws {
        let object = try json(payload)
        #expect(object["placeTextLat"] == nil && object["placeTextLng"] == nil)
    }

    @Test func coordinatesGoOutAsNullWhenTheAddressChanged() throws {
        var cleared = payload
        cleared.placeText = "New address"
        cleared.clearPlaceCoordinates = true
        let object = try json(cleared)
        #expect(object["placeTextLat"] is NSNull && object["placeTextLng"] is NSNull)
    }

    @Test func repeatLeavesOutTheDayOfWeek() throws {
        let object = try json(RepeatRequest(recurType: "weekly", recurFrequency: 1, recurEndDate: "2026-12-31", recurException: "skip"))
        #expect(Set(object.keys) == ["recurType", "recurFrequency", "recurEndDate", "recurException"])
    }

    @Test func aFormGoesOutWithEveryKey() throws {
        var form = TaskForm()
        form.projectId = "p"
        form.userIds = ["u"]
        form.statusId = "s"
        form.startDate = "2026-11-05"
        let object = try json(form.payload(references: References(), canLock: false))
        #expect(Set(object.keys) == ["projectId", "userIds", "statusId", "startDate", "endDate", "startTime", "endTime", "title",
                                     "notes", "link", "placeId", "placeText", "resourceId", "isMilestone"])
    }
}
