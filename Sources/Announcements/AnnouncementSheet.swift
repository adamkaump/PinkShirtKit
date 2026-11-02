import SwiftUI

extension View {
    /// Shows the newest announcement this person hasn't seen, as a sheet, once per launch.
    ///
    ///     ContentView()
    ///         .announcements(from: URL(string: "https://pinkshirtfriday.com/announcements/pinpoint.json")!)
    ///
    /// Launch with `-PSFAnnouncementsShowSeen YES` to see announcements again while testing.
    /// Showing one, and tapping its link, are counted anonymously unless `UsageReporting.isEnabled` is off.
    /// Pass `isEnabled: false` for launches that shouldn't show one, such as screenshot runs.
    public func announcements(from feedURL: URL, isEnabled: Bool = true) -> some View {
        modifier(AnnouncementsModifier(feedURL: feedURL, isEnabled: isEnabled))
    }
}

/// An announcement narrowed to the one language it will be shown in.
public struct ResolvedAnnouncement: Identifiable, Sendable {
    public var id: String
    public var language: String
    public var content: Announcement.Content
    public var link: URL?
    /// The feed's name, such as "pinpoint", for view counts.
    var app: String?
}

@MainActor
public enum AnnouncementChecker {
    static let seenKey = "PSFAnnouncements.seen"
    static let showSeenKey = "PSFAnnouncementsShowSeen"
    private static var hasChecked = false

    /// Fetches the feed and picks what to show, at most once per launch. Fails quietly: no network, no sheet.
    static func nextAnnouncement(from feedURL: URL, defaults: UserDefaults = .standard) async -> ResolvedAnnouncement? {
        guard !hasChecked else { return nil }
        hasChecked = true
        // The shared URL cache revalidates with the server's ETag, so an unchanged feed isn't downloaded again.
        let request = URLRequest(url: feedURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let feed = try? AnnouncementFeed.decoder.decode(AnnouncementFeed.self, from: data)
        else { return nil }

        let seen = defaults.bool(forKey: showSeenKey) ? [] : Set(defaults.stringArray(forKey: seenKey) ?? [])
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let next = select(from: feed, appVersion: version, build: build, seen: seen, preferences: Locale.preferredLanguages) else { return nil }
        markSeen(next.id, defaults: defaults)
        var shown = next
        shown.app = feedURL.deletingPathExtension().lastPathComponent
        UsageReporting.recordAnnouncement(shown, kind: "view")
        return shown
    }

    /// The newest live announcement for this version that isn't in `seen`.
    public static func select(from feed: AnnouncementFeed, appVersion: String, build: String? = nil, seen: Set<String>, preferences: [String], now: Date = .now) -> ResolvedAnnouncement? {
        guard feed.schema <= AnnouncementFeed.currentSchema else { return nil }
        let candidate = feed.announcements
            .filter { $0.isLive(at: now, appVersion: appVersion, build: build) && !seen.contains($0.id) }
            .max { $0.publishedAt < $1.publishedAt }
        guard let candidate, let language = candidate.language(for: preferences),
              let content = candidate.localizations[language]
        else { return nil }
        return ResolvedAnnouncement(id: candidate.id, language: language, content: content, link: candidate.link)
    }

    /// Recorded when shown, so swiping the sheet away counts too. Keeps the last 100.
    private static func markSeen(_ id: String, defaults: UserDefaults) {
        var seen = defaults.stringArray(forKey: seenKey) ?? []
        seen.append(id)
        defaults.set(Array(seen.suffix(100)), forKey: seenKey)
    }
}

struct AnnouncementsModifier: ViewModifier {
    let feedURL: URL
    let isEnabled: Bool
    @State private var announcement: ResolvedAnnouncement?

    func body(content: Content) -> some View {
        content
            .task {
                guard isEnabled else { return }
                announcement = await AnnouncementChecker.nextAnnouncement(from: feedURL)
            }
            .sheet(item: $announcement) { announcement in
                AnnouncementSheet(announcement: announcement)
            }
    }
}

public struct AnnouncementSheet: View {
    let announcement: ResolvedAnnouncement
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(announcement: ResolvedAnnouncement) {
        self.announcement = announcement
    }

    private var content: Announcement.Content { announcement.content }

    private var body_: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: content.body, options: options)) ?? AttributedString(content.body)
    }

    private var linkTitle: String {
        if let title = content.linkTitle, !title.isEmpty { return title }
        return Self.localized("Learn More", language: announcement.language)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(body_)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 10) {
                if let link = announcement.link {
                    Button {
                        UsageReporting.recordAnnouncement(announcement, kind: "link")
                        openURL(link)
                        dismiss()
                    } label: {
                        Text(linkTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        dismiss()
                    } label: {
                        Text(Self.localized("OK", language: announcement.language)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text(Self.localized("OK", language: announcement.language)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .environment(\.locale, Locale(identifier: announcement.language))
        #if os(macOS)
        .frame(width: 440)
        .frame(minHeight: 220, maxHeight: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    /// The button labels follow the announcement's language, which can differ from the app's.
    static func localized(_ key: String, language: String) -> String {
        if let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }
}

#Preview {
    AnnouncementSheet(announcement: ResolvedAnnouncement(
        id: "preview",
        language: "en",
        content: .init(title: "Pinpoint 2.0 is here", body: "New **flags** quiz, plus a fresh look for the map.", linkTitle: "See What's New"),
        link: URL(string: "https://pinkshirtfriday.com/pinpoint/")
    ))
}
