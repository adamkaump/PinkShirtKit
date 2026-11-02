# Announcements

Shows announcements written in Megaphone as a sheet when a Pink Shirt Friday app launches.

```swift
import Announcements

WindowGroup {
    ContentView()
        .announcements(from: URL(string: "https://pinkshirtfriday.com/announcements/pinpoint.json")!)
}
```

- The feed is checked once per launch. A person sees each announcement once, in the closest of its
  languages to their own, with English as the fallback.
- No network, a bad file or a newer feed schema all mean no sheet.
- To see announcements again while testing, launch with `-PSFAnnouncementsShowSeen YES`.
- The feed format lives in `Feed.swift`. Megaphone writes the same shape, so change both together.
- Feeds: `kitchen-sync.json`, `pinpoint.json` and `spider-solitaire.json` under
  https://pinkshirtfriday.com/announcements/.
- The button labels ship in all 18 Tier 1 and Tier 2 languages.

Run the tests with `swift test`.
