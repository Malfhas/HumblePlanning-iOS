import Foundation
import Testing
@testable import HumbleCore

/// Port of `ChatQuotaTest`: the quota of `/api/ai-chat/access`, read like the web gauge.
struct ChatQuotaTests {
    private func state(_ json: String) throws -> AssistantState {
        try JSONDecoder().decode(AssistantState.self, from: Data(json.utf8))
    }

    @Test func readsTheQuotaOfTheServer() throws {
        let quota = try #require(try state("""
            {"enabled":true,"level":"WRITE","quota":{"enabled":true,"unlimited":false,"percent":42,"reached":false,"resetsAt":"2026-12-01T00:00:00.000Z"}}
            """).quota)
        #expect(quota.percent == 42)
        #expect(quota.resetsAt == "2026-12-01T00:00:00.000Z")
        #expect(!quota.blocksQuestions)
    }

    @Test func noQuotaFromAnOlderServer() throws {
        #expect(try state(#"{"enabled":true}"#).quota == nil)
        #expect(try state(#"{"enabled":true,"quota":null}"#).quota == nil)
    }

    @Test func missingOrNullFieldsTakeTheirDefault() throws {
        let quota = try #require(try state(#"{"quota":{"enabled":true,"percent":null}}"#).quota)
        #expect(quota == ChatQuota(enabled: true))
    }

    @Test func coloursLikeTheWeb() {
        #expect(ChatQuota(enabled: true, percent: 69).level == .success)
        #expect(ChatQuota(enabled: true, percent: 70).level == .warning)
        #expect(ChatQuota(enabled: true, percent: 89).level == .warning)
        #expect(ChatQuota(enabled: true, percent: 90).level == .danger)
    }

    @Test func onlyAReachedQuotaOfALimitedAccountBlocksQuestions() {
        #expect(ChatQuota(enabled: true, percent: 100, reached: true).blocksQuestions)
        #expect(!ChatQuota(enabled: true, unlimited: true, percent: 100, reached: true).blocksQuestions)
        #expect(!ChatQuota(enabled: false, percent: 100, reached: true).blocksQuestions)
        #expect(!ChatQuota(enabled: true, percent: 100, reached: false).blocksQuestions)
    }
}
