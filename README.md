# Announcements

Pink Shirt Friday's shared app services, all read in Megaphone:

- Announcements written in Megaphone, shown as a sheet on launch.
- Anonymous daily, weekly and monthly user counts.
- A feedback form.

```swift
import Announcements

WindowGroup {
    ContentView()
        .announcements(from: URL(string: "https://pinkshirtfriday.com/announcements/pinpoint.json")!)
        .usageReporting(app: "pinpoint")
}

// In settings or a menu:
Button("Send Feedback") { showingFeedback = true }
    .feedbackSheet(isPresented: $showingFeedback, app: "pinpoint")
```

The app name matches the feed's file name and the backend's list of apps: `kitchen-sync`, `pinpoint` or
`spider-solitaire`.

## Announcements

- The feed is checked once per launch. A person sees each announcement once, in the closest of its
  languages to their own, with English as the fallback.
- No network, a bad file or a newer feed schema all mean no sheet.
- To see announcements again while testing, launch with `-PSFAnnouncementsShowSeen YES`.
- The feed format lives in `Feed.swift`. Megaphone writes the same shape, so change both together.
- Feeds: `kitchen-sync.json`, `pinpoint.json` and `spider-solitaire.json` under
  https://pinkshirtfriday.com/announcements/.
- The button labels ship in all 18 Tier 1 and Tier 2 languages.
- Version rules can include a build number: `below` "2.1" with `belowBuild` "45" also reaches 2.1 builds under 45.

## Usage and feedback

- Usage reports go to the pinkshirtfriday-api Worker (`../pinkshirtfriday-api`), at most once per UTC day per
  install, with no identifier. Each says whether it's also the install's first of the ISO week and of the month,
  which is how the server counts weekly and monthly users. Showing an announcement and tapping its link are
  counted too.
- Debug builds don't report unless launched with `-PSFUsageDebug YES`, and simulators never do.
- The last report's day, week and month are kept in the Keychain as well as UserDefaults, so deleting and
  reinstalling on iPhone or iPad the same day isn't counted twice.
- Turn reporting off with `UsageReporting.isEnabled = false`, or a toggle on
  `@AppStorage(UsageReporting.disabledKey)` (true means off). Feedback is sent either way, since the person
  chose to send it.
- `PrivacyInfo.xcprivacy` declares what's collected. Each app's App Store privacy details have to match:
  Product Interaction and Other Diagnostic Data (not linked, analytics), and Customer Support and Email Address
  (linked, app functionality).
- The feedback form's text ships in all 18 languages.

Run the tests with `swift test`.
