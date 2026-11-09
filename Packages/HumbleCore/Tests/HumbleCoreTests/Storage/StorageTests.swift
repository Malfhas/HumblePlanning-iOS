import Foundation
import Testing
@testable import HumbleCore

struct StorageTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "hp-\(UUID().uuidString)")

    @Test func encryptedRoundTrip() throws {
        let secrets = MemorySecretStore()
        let files = EncryptedFiles(directory: directory, secrets: secrets)
        defer { files.deleteAll() }
        let tasks = [PlanningTask(id: "t1", title: "Visite", startDate: "2026-11-05", users: [User(id: "u", name: "Turner")])]
        try files.write(tasks, .tasks)
        #expect(files.read([PlanningTask].self, .tasks) == tasks)
        let raw = try Data(contentsOf: directory.appending(path: "tasks.bin"))
        #expect(!String(decoding: raw, as: UTF8.self).contains("Visite"))
        #expect(raw.count == 12 + (try JSONEncoder().encode(tasks)).count + 16)
    }

    @Test func otherKeyReadsAsAbsent() throws {
        let files = EncryptedFiles(directory: directory, secrets: MemorySecretStore())
        defer { files.deleteAll() }
        try files.write(["a"], .references)
        #expect(EncryptedFiles(directory: directory, secrets: MemorySecretStore()).read([String].self, .references) == nil)
        files.delete(.references)
        #expect(files.read([String].self, .references) == nil)
    }

    @Test func session() {
        let store = SessionStore(secrets: MemorySecretStore())
        #expect(store.load() == nil)
        let session = ServerSession(serverURL: "https://p.example.com", cookieName: "n", cookieValue: "v")
        store.save(session)
        #expect(store.load() == session)
        store.save(nil)
        #expect(store.load() == nil)
    }

    @Test func alertsShownKeepsTheLatest200() {
        let defaults = UserDefaults(suiteName: "hp-tests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.alertsShown = (1...250).map(String.init)
        #expect(preferences.alertsShown.count == 200)
        #expect(preferences.alertsShown.first == "51")
        #expect(preferences.rememberMe && preferences.reminderOffset == "15min" && preferences.theme == "system")
    }
}
