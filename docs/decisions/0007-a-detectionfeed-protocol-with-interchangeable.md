# D7. A `DetectionFeed` protocol with interchangeable sources

Status: accepted (2026-10-01)

`FixtureFeed` (demo mode, previews, tests), `ServerFeed` (simulator), and later
`FireWatchFeed` (real data). *Why:* this is how the fake data gets replaced without
touching the UI. It's the dependency-inversion principle in practice.
