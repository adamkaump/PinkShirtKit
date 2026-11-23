# PinkShirtKit

Pink Shirt Friday's shared app services, all read in Megaphone:

- Announcements written in Megaphone, shown as a sheet on launch.
- Usage: users, sessions and time in app, under a random install ID.
- A feedback form.

```swift
import PinkShirtKit

WindowGroup {
    ContentView()
        .announcements(from: URL(string: "https://pinkshirtfriday.com/announcements/pinpoint.json")!)
        .usageReporting(app: "pinpoint")
}

// In settings or a menu:
Button("Send Feedback") { showingFeedback = true }
    .feedbackSheet(isPresented: $showingFeedback, app: "pinpoint")
```

The app name matches the feed's file name and the backend's list of apps: `kitchen-sync`, `media-client`,
`pinpoint`, `schooldash` or `spider-solitaire`.

Runs on iOS, iPadOS, macOS, tvOS and visionOS. tvOS gets announcements and usage reporting but no feedback form,
since it has no text editor for writing a message.

## Announcements

- The feed is checked when the app comes to the front, at most once an hour, and never during a background
  launch. An announcement counts as seen once its sheet appears. A person sees each announcement once, in the closest of its
  languages to their own, with English as the fallback.
- No network, a bad file or a newer feed schema all mean no sheet.
- To see announcements again while testing, launch with `-PSFAnnouncementsShowSeen YES`.
- The feed format lives in `Feed.swift`. Megaphone writes the same shape, so change both together.
- Feeds: `kitchen-sync.json`, `pinpoint.json` and `spider-solitaire.json` under
  https://pinkshirtfriday.com/announcements/.
- The button labels ship in all 18 Tier 1 and Tier 2 languages.
- Version rules can include a build number: `below` "2.1" with `belowBuild` "45" also reaches 2.1 builds under 45.

## Usage and feedback

- Each install makes a random ID (a UUID) and replaces it after a year. It's never tied to an account or sent to
  anyone else, and it's kept in the Keychain so a reinstall keeps it.
- A usage report goes to the pinkshirtfriday-api Worker (`../pinkshirtfriday-api`) once a UTC day, and when the
  ID changes, with the ID, app version, platform, device model, system version and language. Showing an
  announcement and tapping its link are counted too.
- While the app is on screen it sends a heartbeat each minute with the ID, app version and whether a session is
  starting (after 5 minutes or more away). The server joins these into sessions with start and end times, so
  Megaphone can count users, sessions and minutes per day in any time zone, and people using the app now.
- Debug builds don't report unless launched with `-PSFUsageDebug YES`. Simulators and Apple's virtual devices
  (iPhone99,x, VirtualMac), which launch every uploaded build, never do.
- The ID and the last report's day are kept in the Keychain as well as UserDefaults, so deleting and
  reinstalling on iPhone or iPad isn't counted as someone new.
- Turn reporting off with `UsageReporting.isEnabled = false`, or a toggle on
  `@AppStorage(UsageReporting.disabledKey)` (true means off). Feedback is sent either way, since the person
  chose to send it.
- `PrivacyInfo.xcprivacy` declares what's collected. Each app's App Store privacy details have to match:
  Device ID, Product Interaction and Other Diagnostic Data (not linked, analytics), and Customer Support and Email
  Address (linked, app functionality).
- The feedback form's text ships in all 18 languages.

Called Announcements before 2.0.0; GitHub redirects the old repository address.

Run the tests with `swift test`.
