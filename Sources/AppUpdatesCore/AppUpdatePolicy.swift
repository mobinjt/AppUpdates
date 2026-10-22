import Foundation

/// Which app builds a backend still serves, and which it suggests updating from, for one
/// platform.
///
/// The app reads it when it opens and comes to the foreground. Every request the app makes names
/// its platform and build in `buildHeader`; a backend can answer builds below `minimumBuild` with
/// 426 Upgrade Required and this policy as the body.
public struct AppUpdatePolicy: Codable, Hashable, Sendable {
    /// `ios 42`: the platform and the build number (`CFBundleVersion`).
    public static let buildHeader = "X-App-Build"
    /// The longest message a policy can carry.
    public static let maximumMessageLength = 300

    public enum Platform: String, Codable, CaseIterable, Hashable, Sendable {
        /// iPhone, iPad and Vision Pro.
        case iOS = "ios"
        case macOS = "macos"
    }

    public enum Status: Hashable, Sendable {
        case upToDate
        /// A newer build is recommended; the user may keep going.
        case suggested(build: Int)
        /// This build is below the minimum: the app can't be used until it's updated.
        case required
    }

    public let platform: Platform
    /// Builds below this one must update; `nil` lets every build in.
    public let minimumBuild: Int?
    /// Builds below this one are asked to update; `nil` asks none.
    public let recommendedBuild: Int?
    /// Where the Update button goes: the App Store page or the TestFlight link.
    public let updateURL: String?
    /// An optional note from the team, shown with the prompt as written.
    public let message: String?

    public init(platform: Platform, minimumBuild: Int? = nil, recommendedBuild: Int? = nil, updateURL: String? = nil, message: String? = nil) {
        self.platform = platform
        self.minimumBuild = minimumBuild
        self.recommendedBuild = recommendedBuild
        self.updateURL = updateURL
        self.message = message
    }

    public func status(forBuild build: Int) -> Status {
        if let minimumBuild, build < minimumBuild {
            return .required
        }
        if let recommendedBuild, build < recommendedBuild {
            return .suggested(build: recommendedBuild)
        }
        return .upToDate
    }

    /// What's wrong with a policy someone wrote, if anything, for the screen where it's edited.
    public var problem: String? {
        if let minimumBuild, minimumBuild < 1 { return "Builds start at 1." }
        if let recommendedBuild, recommendedBuild < 1 { return "Builds start at 1." }
        if let minimumBuild, let recommendedBuild, recommendedBuild < minimumBuild {
            return "The recommended build can't be below the minimum."
        }
        if let updateURL, !Self.isAllowedURL(updateURL) {
            return "The update link must start with https://, itms-apps:// or itms-beta://."
        }
        if let message, message.count > Self.maximumMessageLength {
            return "The message is longer than \(Self.maximumMessageLength) characters."
        }
        return nil
    }

    private static func isAllowedURL(_ text: String) -> Bool {
        ["https://", "itms-apps://", "itms-beta://"].contains { text.lowercased().hasPrefix($0) } && text.count <= 500
    }

    // MARK: The build header

    public static func headerValue(platform: Platform, build: Int) -> String {
        "\(platform.rawValue) \(build)"
    }

    /// The platform and build in a `buildHeader` value; `nil` when it can't be read.
    public static func parseHeader(_ value: String) -> (platform: Platform, build: Int)? {
        let parts = value.split(separator: " ")
        guard parts.count == 2, let platform = Platform(rawValue: String(parts[0])), let build = Int(parts[1]) else { return nil }
        return (platform, build)
    }
}
