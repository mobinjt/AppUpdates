@_exported import AppUpdatesCore
import Foundation
import Observation
import OSLog

/// Whether this build must or should be updated, from the policy the app's backend holds.
///
/// Check when the app opens and comes to the foreground, and `apply` the policy whenever the
/// backend turns a request away as too old (426). The last policy is kept, so a required update
/// still shows offline. A suggested update is offered once per recommended build.
@MainActor
@Observable
public final class AppUpdateChecker {
    public let platform: AppUpdatePolicy.Platform
    public let build: Int
    public private(set) var policy: AppUpdatePolicy?
    private var dismissedBuild: Int?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: (@Sendable (AppUpdatePolicy.Platform) async throws -> AppUpdatePolicy)?
    @ObservationIgnored private var lastCheck: ContinuousClock.Instant?
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppUpdates", category: "updates")
    private static let policyKey = "appUpdate.policy"
    private static let dismissedBuildKey = "appUpdate.dismissedBuild"

    /// - Parameters:
    ///   - platform: this app's platform; the running one by default.
    ///   - build: this app's build; `CFBundleVersion` by default.
    ///   - defaults: where the last policy and a dismissed suggestion are kept.
    ///   - fetch: reads the backend's policy; `nil` without a backend.
    public init(
        platform: AppUpdatePolicy.Platform = .current,
        build: Int = AppUpdatePolicy.currentBuild,
        defaults: UserDefaults,
        fetch: (@Sendable (AppUpdatePolicy.Platform) async throws -> AppUpdatePolicy)?
    ) {
        self.platform = platform
        self.build = build
        self.defaults = defaults
        self.fetch = fetch
        policy = defaults.data(forKey: Self.policyKey).flatMap { try? JSONDecoder().decode(AppUpdatePolicy.self, from: $0) }
        dismissedBuild = defaults.object(forKey: Self.dismissedBuildKey) as? Int
    }

    public var status: AppUpdatePolicy.Status {
        policy?.status(forBuild: build) ?? .upToDate
    }

    public var isRequired: Bool {
        status == .required
    }

    /// The recommended build, when this one is older.
    public var suggestedBuild: Int? {
        if case .suggested(let build) = status { build } else { nil }
    }

    /// Whether to offer the suggested update now: once per recommended build.
    public var offersSuggestion: Bool {
        suggestedBuild.map { $0 != dismissedBuild } ?? false
    }

    /// The message the team wrote for this update, if any.
    public var message: String? {
        policy?.message
    }

    /// The store page or TestFlight link; TestFlight when none is set.
    public var updateURL: URL? {
        policy?.updateURL.flatMap(URL.init(string:)) ?? URL(string: "itms-beta://")
    }

    /// Stops offering the current suggestion until a newer build is recommended.
    public func dismissSuggestion() {
        guard let suggestedBuild else { return }
        dismissedBuild = suggestedBuild
        defaults.set(suggestedBuild, forKey: Self.dismissedBuildKey)
    }

    /// Reads the backend's policy, at most once per `minimumInterval`.
    public func check(minimumInterval: Duration = .seconds(60)) async {
        guard let fetch else { return }
        if let lastCheck, lastCheck.duration(to: .now) < minimumInterval { return }
        lastCheck = .now
        do {
            apply(try await fetch(platform))
        } catch {
            logger.notice("Update check failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Takes a policy the backend sent, with a 426 or the check. Other platforms' are ignored.
    public func apply(_ policy: AppUpdatePolicy) {
        guard policy.platform == platform, policy != self.policy else { return }
        self.policy = policy
        if let data = try? JSONEncoder().encode(policy) {
            defaults.set(data, forKey: Self.policyKey)
        }
    }
}

extension AppUpdatePolicy.Platform {
    /// The platform this code runs on.
    public static var current: Self {
        #if os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }
}

extension AppUpdatePolicy {
    /// `CFBundleVersion`; 0 when it isn't a number.
    public static let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init) ?? 0

    /// This app's `buildHeader`, to send with every request.
    public static var currentBuildHeaders: [String: String] {
        [buildHeader: headerValue(platform: .current, build: currentBuild)]
    }

    /// The policy in a 426 Upgrade Required answer; `nil` for any other answer.
    public static func upgradeRequired(in data: Data, response: URLResponse?) -> AppUpdatePolicy? {
        guard (response as? HTTPURLResponse)?.statusCode == 426 else { return nil }
        return try? JSONDecoder().decode(AppUpdatePolicy.self, from: data)
    }
}
