import Foundation
@testable import HumbleCore

/// A day written as in the server's JSON.
func day(_ iso: String) -> CalendarDay { CalendarDay(iso)! }

func task(_ id: String, _ start: String, _ end: String? = nil, from: String? = nil, to: String? = nil,
          title: String? = nil, users: [String] = ["u1"], project: String = "p1", status: String = "s1") -> PlanningTask {
    PlanningTask(id: id, title: title, startDate: start, endDate: end, startTime: from, endTime: to, projectId: project,
                 statusId: status, users: users.map { User(id: $0, name: $0) })
}

let paris = TimeZone(identifier: "Europe/Paris")!
let en = Locale(identifier: "en_US")
let fr = Locale(identifier: "fr_FR")
let es = Locale(identifier: "es_ES")
let de = Locale(identifier: "de_DE")

/// A value read from JSON, for the models without a public initializer.
func decoded<T: Decodable>(_ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
