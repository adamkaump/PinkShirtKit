import Foundation

/// The file Megaphone publishes for one app, such as pinkshirtfriday.com/announcements/pinpoint.json.
public struct AnnouncementFeed: Codable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var announcements: [Announcement]

    public init(announcements: [Announcement]) {
        schema = Self.currentSchema
        self.announcements = announcements
    }

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

public struct Announcement: Codable, Sendable, Identifiable {
    public var id: String
    public var publishedAt: Date
    public var expiresAt: Date
    /// Nil shows the announcement on every version.
    public var versions: VersionRule?
    public var link: URL?
    /// Keyed by language code: "en", "de", "zh-Hans", "pt-BR"…
    public var localizations: [String: Content]

    public struct Content: Codable, Sendable, Equatable {
        public var title: String
        /// Markdown: bold, italics and links.
        public var body: String
        /// The link button's label. Empty or nil uses "Learn More".
        public var linkTitle: String?

        public init(title: String, body: String, linkTitle: String? = nil) {
            self.title = title
            self.body = body
            self.linkTitle = linkTitle
        }
    }

    public init(id: String, publishedAt: Date, expiresAt: Date, versions: VersionRule?, link: URL?, localizations: [String: Content]) {
        self.id = id
        self.publishedAt = publishedAt
        self.expiresAt = expiresAt
        self.versions = versions
        self.link = link
        self.localizations = localizations
    }

    public func isLive(at date: Date, appVersion: String, build: String? = nil) -> Bool {
        publishedAt <= date && date < expiresAt && (versions?.matches(appVersion, build: build) ?? true)
    }

    /// The best language for someone whose preferred languages are `preferences`, falling back to English.
    public func language(for preferences: [String]) -> String? {
        let available = Array(localizations.keys)
        if let match = Bundle.preferredLocalizations(from: available, forPreferences: preferences).first,
           preferences.contains(where: { Locale(identifier: $0).language.languageCode == Locale(identifier: match).language.languageCode }) {
            return match
        }
        return localizations["en"] != nil ? "en" : available.sorted().first
    }
}

/// Which versions of an app see an announcement. With both set, a version must satisfy both.
public struct VersionRule: Codable, Sendable, Equatable {
    /// Only versions lower than this, such as "2.1" for a "please update" message.
    public var below: String?
    /// With `below`, also builds of that exact version numbered lower than this: "2.1" and "45" reach 2.1 (44).
    /// Older copies of this package ignore it and leave out every build of `below`.
    public var belowBuild: String?
    /// Only these exact versions.
    public var only: [String]?

    public init(below: String? = nil, belowBuild: String? = nil, only: [String]? = nil) {
        self.below = below
        self.belowBuild = belowBuild
        self.only = only
    }

    /// `build` is CFBundleVersion. Without it, a `belowBuild` rule leaves out the `below` version entirely.
    public func matches(_ version: String, build: String? = nil) -> Bool {
        let current = AppVersion(version)
        if let below {
            let limit = AppVersion(below)
            let earlierBuild = belowBuild.flatMap { belowBuild in build.map { AppVersion($0) < AppVersion(belowBuild) } } ?? false
            guard current < limit || (current == limit && earlierBuild) else { return false }
        }
        if let only, !only.contains(where: { AppVersion($0) == current }) { return false }
        return true
    }
}

/// A dotted version or build number compared part by part, so "1.10" > "1.9" and "2.0" == "2".
public struct AppVersion: Comparable, Sendable {
    let parts: [Int]

    public init(_ string: String) {
        parts = string.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        return lhs.padded(to: count) == rhs.padded(to: count)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        return lhs.padded(to: count).lexicographicallyPrecedes(rhs.padded(to: count))
    }
}
