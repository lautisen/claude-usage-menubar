import Foundation
import Testing
@testable import ClaudeUsage

@MainActor
@Suite("UsageStore")
struct UsageStoreTests {
    let creds = Credentials(accessToken: "tok", expiresAt: nil, subscriptionType: "pro")

    @Test func successfulRefreshPublishesData() async throws {
        let usage = try UsageService.decodeUsage(usageFixture)
        let store = UsageStore(fetcher: { [creds] in (usage, creds) })
        var changes = 0
        store.onChange = { changes += 1 }

        await store.performRefresh()

        #expect(store.sessionPercent == 25)
        #expect(store.plan == "pro")
        #expect(store.error == nil)
        #expect(store.isLoading == false)
        #expect(store.lastUpdated != nil)
        #expect(store.nextRefresh.map { $0 > Date() } == true)
        #expect(changes == 1)
    }

    @Test func failedRefreshKeepsPreviousDataAndShowsError() async throws {
        let usage = try UsageService.decodeUsage(usageFixture)
        var shouldFail = false
        let store = UsageStore(fetcher: { [creds] in
            if shouldFail { throw UsageError.rateLimited }
            return (usage, creds)
        })

        await store.performRefresh()
        shouldFail = true
        await store.performRefresh()

        #expect(store.sessionPercent == 25)
        #expect(store.error == UsageError.rateLimited.errorDescription)
        #expect(store.isLoading == false)
    }

    @Test func recoveringClearsTheError() async throws {
        let usage = try UsageService.decodeUsage(usageFixture)
        var shouldFail = true
        let store = UsageStore(fetcher: { [creds] in
            if shouldFail { throw UsageError.tokenExpired }
            return (usage, creds)
        })

        await store.performRefresh()
        #expect(store.error != nil)
        shouldFail = false
        await store.performRefresh()
        #expect(store.error == nil)
    }

    @Test func staleness() {
        let store = UsageStore(fetcher: { throw UsageError.noCredentials })
        #expect(store.isStale())

        let now = Date()
        store.lastUpdated = now.addingTimeInterval(-29)
        #expect(!store.isStale(now: now))
        store.lastUpdated = now.addingTimeInterval(-30)
        #expect(store.isStale(now: now))
    }
}
