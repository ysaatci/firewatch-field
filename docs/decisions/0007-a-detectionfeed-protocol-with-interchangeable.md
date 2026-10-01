# D7. A `DetectionFeed` protocol with interchangeable sources

Status: accepted (2026-10-01), revised during M2 review.

`SimulatedFeed` (demo mode: the simulator runs on the device), `ServerFeed` (the
simulator server), `FixtureFeed` (previews and snapshot tests: a frozen state), and later
`FireWatchFeed` (real data). *Why:* this is how the fake data gets replaced without
touching the UI. It's the dependency-inversion principle in practice.
*Revised in the M2 review:* demo mode originally replayed bundled JSON. Running the
deterministic simulator on the device is simpler (no fixture files to keep in sync),
reacts to crew actions exactly like the server, and builds a four-hour scenario in about
a second.
