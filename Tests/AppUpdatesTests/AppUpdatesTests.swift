import AppUpdates
import Foundation
import Testing

@MainActor
struct AppUpdateCheckerTests {
    private let defaults = UserDefaults(suiteName: "app-updates-tests-\(UUID().uuidString)")!

    private func checker(build: Int, serving policy: AppUpdatePolicy?, fetches: Counter = Counter()) -> AppUpdateChecker {
        AppUpdateChecker(platform: .iOS, build: build, defaults: defaults, fetch: policy.map { policy in
            { @Sendable _ in
                await fetches.increment()
                return policy
            }
        })
    }

    @Test func buildsBelowTheMinimumMustUpdate() async {
        let updates = checker(build: 9, serving: AppUpdatePolicy(platform: .iOS, minimumBuild: 10, updateURL: "https://testflight.apple.com/join/abc"))
        #expect(!updates.isRequired, "Nothing is known before the first check")
        await updates.check()
        #expect(updates.isRequired)
        #expect(updates.updateURL?.absoluteString == "https://testflight.apple.com/join/abc")
        #expect(!updates.offersSuggestion)
    }

    @Test func aSuggestionIsOfferedOncePerRecommendedBuild() async {
        let updates = checker(build: 10, serving: AppUpdatePolicy(platform: .iOS, recommendedBuild: 12, message: "Something new"))
        await updates.check()
        #expect(updates.suggestedBuild == 12)
        #expect(updates.offersSuggestion)
        #expect(updates.message == "Something new")
        updates.dismissSuggestion()
        #expect(!updates.offersSuggestion)
        #expect(updates.suggestedBuild == 12, "Still known, for a quiet Update row")

        // A newer recommended build is offered again, even after a restart.
        let restarted = checker(build: 10, serving: AppUpdatePolicy(platform: .iOS, recommendedBuild: 12))
        #expect(!restarted.offersSuggestion)
        restarted.apply(AppUpdatePolicy(platform: .iOS, recommendedBuild: 13))
        #expect(restarted.offersSuggestion)
    }

    @Test func theLastPolicyStillAppliesOffline() async {
        let online = checker(build: 9, serving: AppUpdatePolicy(platform: .iOS, minimumBuild: 10))
        await online.check()
        let offline = AppUpdateChecker(platform: .iOS, build: 9, defaults: defaults, fetch: nil)
        #expect(offline.isRequired)
        #expect(offline.updateURL?.absoluteString == "itms-beta://", "TestFlight when no link is set")
        let updated = AppUpdateChecker(platform: .iOS, build: 10, defaults: defaults, fetch: nil)
        #expect(!updated.isRequired, "Updating clears it")
    }

    @Test func otherPlatformsPoliciesAreIgnoredAndChecksAreSpacedOut() async {
        let fetches = Counter()
        let updates = checker(build: 9, serving: AppUpdatePolicy(platform: .iOS), fetches: fetches)
        updates.apply(AppUpdatePolicy(platform: .macOS, minimumBuild: 100))
        #expect(!updates.isRequired)
        await updates.check()
        await updates.check()
        #expect(await fetches.count == 1)
        await updates.check(minimumInterval: .zero)
        #expect(await fetches.count == 2)
    }

    @Test func aTurnAwayCarriesThePolicy() throws {
        let policy = AppUpdatePolicy(platform: .iOS, minimumBuild: 10)
        let data = try JSONEncoder().encode(policy)
        let url = URL(string: "https://example.com/v1/me")!
        let turnedAway = HTTPURLResponse(url: url, statusCode: 426, httpVersion: nil, headerFields: nil)
        let fine = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        #expect(AppUpdatePolicy.upgradeRequired(in: data, response: turnedAway) == policy)
        #expect(AppUpdatePolicy.upgradeRequired(in: data, response: fine) == nil)
    }
}

struct AppUpdatePolicyTests {
    @Test func theStatusFollowsTheBuild() {
        let policy = AppUpdatePolicy(platform: .iOS, minimumBuild: 10, recommendedBuild: 12)
        #expect(policy.status(forBuild: 9) == .required)
        #expect(policy.status(forBuild: 10) == .suggested(build: 12))
        #expect(policy.status(forBuild: 12) == .upToDate)
        #expect(AppUpdatePolicy(platform: .iOS).status(forBuild: 1) == .upToDate)
    }

    @Test func theBuildHeaderRoundTrips() {
        let value = AppUpdatePolicy.headerValue(platform: .macOS, build: 42)
        #expect(value == "macos 42")
        let parsed = AppUpdatePolicy.parseHeader(value)
        #expect(parsed?.platform == .macOS)
        #expect(parsed?.build == 42)
        #expect(AppUpdatePolicy.parseHeader("ios") == nil)
        #expect(AppUpdatePolicy.parseHeader("android 3") == nil)
    }

    @Test func badPoliciesSayWhy() {
        #expect(AppUpdatePolicy(platform: .iOS, minimumBuild: 0).problem != nil)
        #expect(AppUpdatePolicy(platform: .iOS, minimumBuild: 10, recommendedBuild: 9).problem != nil)
        #expect(AppUpdatePolicy(platform: .iOS, updateURL: "http://example.com").problem != nil)
        #expect(AppUpdatePolicy(platform: .iOS, message: String(repeating: "a", count: 301)).problem != nil)
        #expect(AppUpdatePolicy(platform: .iOS, minimumBuild: 10, recommendedBuild: 12, updateURL: "itms-beta://").problem == nil)
    }
}

actor Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
