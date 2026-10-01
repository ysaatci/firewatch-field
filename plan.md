# FireWatch Field — Plan

An iOS app for wildfire ground crews. It shows drone-detected hotspots and the live fire
perimeter, lets crews claim and close out hotspots during mop-up, and keeps working with
no signal. Until the real FireWatch drone pipeline exists, a **deterministic fake-data
simulator** written in Swift supplies the data. It uses the same API contract the real
pipeline will use later.

The project is built on Windows with no Mac. All logic lives in a Swift package that
builds and tests on Linux (in Docker). Only the thin SwiftUI layer needs macOS, and that
is built, tested and screenshotted on GitHub Actions macOS runners.

**Working rule:** each checkbox is one small Conventional Commit, and the box is ticked
in that same commit. Always continue from the first unchecked step.

---

## 1. Scope

### Users
| Persona | Need |
|---|---|
| **Mop-up crew member** (primary) | "Which hot spots near me are still burning, and how do I get there?" |
| **Crew lead** | "Assign hotspots to people, see what's done, report new sightings." |
| **Recruiter / reviewer** (the real audience for now) | Can understand and see the app in 2 minutes from the README, and run it with no server. |

### Out of scope (for now)
- Real authentication and user accounts. A static dev token is used; see D11.
- Controlling drones from the app.
- Android. It's a possible later milestone, sharing the same server.
- Real FireWatch data. M16 swaps it in behind the existing protocol.

---

## 2. Functional requirements

### App
| ID | Requirement |
|---|---|
| FR-1 | **Map** shows active hotspots, colour- **and** shape-coded by severity, clustered when zoomed out. |
| FR-2 | **Fire perimeter** is drawn as a polygon with its timestamp. A timeline scrubber shows how the perimeter changed. |
| FR-3 | **Drones** are shown live with their position and recent track. |
| FR-4 | **Hotspot list** is sorted by priority (temperature × recency × distance from the user), with filters by status and severity. |
| FR-5 | **Hotspot detail** shows temperature, confidence, first/last seen, a temperature trend sparkline, distance and bearing, and an "Open in Maps" directions button. |
| FR-6 | **Hotspot workflow**: `new → assigned → extinguished → verifiedCold` (or `→ flaredUp → assigned`). Status changes sync to the server. |
| FR-7 | **Report a sighting**: photo, GPS position, severity and note. Works offline (queued). |
| FR-8 | **Alerts**: a new hotspot or flare-up within *R* km of the user triggers an in-app banner and a local notification. |
| FR-9 | **Offline mode**: the last-known data stays usable, a banner shows how stale it is, and a badge shows the number of queued actions. |
| FR-10 | **Settings**: data source (Demo / Server URL), alert radius, units (metric/imperial), language (EN/TR). |
| FR-11 | **Demo mode**: runs the simulator on the device, with no server. This is the default on first launch. |

### Simulator server
| ID | Requirement |
|---|---|
| FR-S1 | REST: current snapshot, hotspots in a bounding box, perimeter history, drones. |
| FR-S2 | WebSocket stream of events (`hotspotDetected`, `hotspotUpdated`, `perimeterUpdated`, `droneMoved`). |
| FR-S3 | Replay control: start, pause, speed (1×–600×), reset, and seed selection. |
| FR-S4 | Accepts sighting reports and status changes, idempotently. |
| FR-S5 | Fault injection: added latency, a drop rate and forced disconnects, so the offline behaviour can be demonstrated. |

---

## 3. Non-functional requirements

| ID | Category | Requirement | How it's verified |
|---|---|---|---|
| NFR-1 | Platform | iOS 17+, iPhone first, iPad layout acceptable. | CI builds on both simulators. |
| NFR-2 | Performance | The map stays smooth (no hitches) with **2,000 hotspots**. Cached data appears < 1 s after launch. | `XCTOSSignpostMetric` / `XCTApplicationLaunchMetric` tests with a stress fixture. |
| NFR-3 | Offline | Every read feature works from cache. **Zero loss** of queued writes across app kill and relaunch. | Core outbox tests, plus a UI test that kills and relaunches the app. |
| NFR-4 | Reliability | WebSocket reconnects with exponential backoff and jitter. All writes are idempotent (client-generated UUIDs). | Core tests with a fake transport and a fake clock. Server idempotency tests. |
| NFR-5 | Battery | No continuous background GPS. WebSocket runs only in the foreground. Background refresh uses `BGAppRefreshTask`. | Code review checklist. |
| NFR-6 | Accessibility | Dynamic Type up to AX5. VoiceOver labels on map annotations. Severity is never shown by colour alone. Readable in direct sunlight (high-contrast palette). | Accessibility audit in UI tests (`performAccessibilityAudit`). |
| NFR-7 | Localisation | English and Turkish via String Catalogs. | Snapshot tests in both locales. |
| NFR-8 | Security & privacy | Token stored in Keychain. "When in use" location only. ATS exception for localhost only. No coordinates or tokens in logs. Photo EXIF stripped except GPS. | Tests and review. |
| NFR-9 | Testability | `FireWatchCore` ≥ 80 % line coverage and builds/tests on **Linux**. Primary user flows covered by UI tests. | CI coverage report. |
| NFR-10 | Maintainability | Swift 6 language mode (strict concurrency), zero warnings, swift-format enforced, DocC for public Core API. | CI fails on warnings and on format diffs. |
| NFR-11 | Portability | `FireWatchCore` and `FireWatchAPI` import no Apple-only frameworks, so the real FireWatch backend can reuse them. | Linux CI job. |
| NFR-12 | Determinism | The same seed always produces the same scenario, byte-for-byte. | Golden-file tests. |
| NFR-13 | CI cost | Linux job < 5 min. macOS job < 15 min and runs only on PRs and `main`. | Workflow timing. |

---

## 4. Architecture

```
firewatch-field/
├─ Package.swift                 (SwiftPM: Core, API, Simulator, Server, CLI)
├─ Sources/
│  ├─ FireWatchCore/             domain, geo math, ranking, sync engine, feeds   ← Linux + iOS
│  ├─ FireWatchAPI/              Codable DTOs + GeoJSON, versioned contract      ← Linux + iOS
│  ├─ FireWatchSimulator/        seeded fire-spread scenario generator           ← Linux + iOS
│  ├─ FireWatchServer/           Vapor app: REST + WebSocket + replay + faults   ← Linux (Docker)
│  └─ fwgen/                     CLI: export scenarios as JSON fixtures
├─ Tests/                        XCTest / Swift Testing for all of the above
├─ App/
│  ├─ project.yml                XcodeGen spec (the .xcodeproj is generated in CI, never committed)
│  ├─ FireWatchField/            SwiftUI app (Features/, Persistence/, Resources/)
│  ├─ FireWatchFieldTests/       app-level unit + snapshot tests
│  └─ FireWatchFieldUITests/     flows + screenshot capture
├─ docker/                       dev image, compose for the server
├─ docs/                         api.md, architecture.md, decisions/
└─ .github/workflows/            ci-linux.yml, ci-ios.yml
```

### Data flow
```
FireWatchSimulator ─► FireWatchServer ─REST/WS─► ServerFeed ─────┐
        │                                                        ├─► FeedStore (actor) ─► ViewModels ─► SwiftUI
        └─── in-process, demo mode ─────────────► SimulatedFeed ─┘      │
                                                                     Outbox (actor) ──► server (writes)
                                                                        │
                                                                     Persistence (SwiftData, app layer)
```

---

## 5. Design decisions

Each decision gives the choice, the main alternative, and why. These are worth being
able to explain in an interview.

**D1. Logic in a platform-neutral Swift package, with a thin UI layer.**
*Alternative:* everything in the app target.
*Why:* without a Mac, the only code you can iterate on quickly is code that builds on
Linux. It's also good architecture: domain logic stays testable without a simulator, and
the same Core can later run inside the real FireWatch backend (NFR-11).

**D2. Develop locally in a Linux Docker image, not with the native Windows toolchain.**
*Alternative:* the Swift for Windows toolchain.
*Why:* Smart App Control on this machine blocks unsigned compiled test binaries (this
already happened with Go). Vapor/SwiftNIO support on Windows is also weaker than on
Linux. Docker matches CI exactly. The native Windows toolchain is optional, mainly for
editor support.

**D3. XcodeGen (`project.yml`) instead of a committed `.xcodeproj`.**
*Alternative:* a hand-made Xcode project, or Tuist.
*Why:* you can't create or reliably edit `.pbxproj` files without Xcode. A YAML spec is
readable, merges cleanly, and CI generates the project. Tuist is more powerful but
heavier than this project needs.

**D4. Deterministic, seeded fake data instead of random or hand-written JSON.**
*Alternative:* a few static JSON files.
*Why:* a believable demo needs fire that *moves*: a spreading front, residual hotspots
that cool, and occasional flare-ups. Seeding (SplitMix64, because Foundation's RNG
can't be seeded) makes tests and screenshots reproducible (NFR-12). One generator feeds
the server, the app's demo mode and the tests, so they never disagree.

**D5. The fire model is a simple cellular automaton, not real fire physics.**
A grid of roughly 50 m cells with fuel, slope and wind factors. Each burning cell can
ignite its neighbours with a probability that is biased downwind. Burned cells leave
hotspots that cool exponentially and flare up with a small probability. *Why:* it looks
right, is cheap to compute, and is easy to explain. Realism isn't the point; the app is.
It's also a natural link to FireWatch's own simulation-first approach. The default
scenario is centred near Manavgat, Antalya.

**D6. A shared `FireWatchAPI` contract module, using GeoJSON for geometry.**
*Alternative:* separate DTOs on the client and the server.
*Why:* one Codable definition, imported by both sides, makes contract drift a compile
error. GeoJSON is what GIS tools and the real drone pipeline will produce. Paths are
versioned (`/v1`) and every payload carries `schemaVersion`.

**D7. A `DetectionFeed` protocol with interchangeable sources.**
`SimulatedFeed` (demo mode: the simulator runs on the device), `ServerFeed` (the
simulator server), `FixtureFeed` (previews and snapshot tests: a frozen state), and later
`FireWatchFeed` (real data). *Why:* this is how the fake data gets replaced without
touching the UI. It's the dependency-inversion principle in practice.
*Revised in the M2 review:* demo mode originally replayed bundled JSON. Running the
deterministic simulator on the device is simpler (no fixture files to keep in sync),
reacts to crew actions exactly like the server, and builds a four-hour scenario in about
a second.

**D8. MVVM with `@Observable`, no TCA.**
*Alternative:* The Composable Architecture.
*Why:* it has no third-party dependency, it's the approach Apple promotes, and it's
easy for a reviewer to follow. Testable logic sits in Core actors anyway, so view models
stay thin. The trade-off (less enforced structure than TCA) is acceptable at this size.

**D9. Offline-first with an outbox; conflicts resolved by replaying workflow actions.**
Writes go to a persistent outbox (client UUID, attempt count, next retry time) and are
flushed when connectivity returns. Crews send *actions* (`assign`, `extinguish`, …), not
target statuses. *Conflict policy:* the server is authoritative for detections
(temperature, position) and applies each queued action only if the workflow state
machine allows it from the hotspot's **current** status, rejecting it otherwise. On the
device, the displayed state is the server state with still-pending actions replayed on
top (an optimistic rebase); a rejected action is dropped and the user is told.
*Example:* a crew marks a hotspot `verifyCold` offline, but a drone saw it flare up in the
meantime. `verifyCold` isn't legal from `flaredUp`, so it's rejected, and the crew sees the
flare-up instead of a false "cold".
*Alternative considered:* "most advanced status wins". It breaks on flare-ups (a cycle,
not a line) and on unassign (a legitimate step backwards).
*Why:* this is the real need for crews out of signal, and a strong interview topic.

**D10. SwiftData for the cache and outbox in the app; storage protocols in Core.**
*Alternative:* GRDB/SQLite inside Core, which would also be testable on Linux.
*Why:* SwiftData is the modern Apple stack recruiters look for. Core defines
`HotspotStore` and `OutboxStore` protocols with in-memory implementations, so the sync
*logic* is fully tested on Linux. Only the thin SwiftData adapter is tested on macOS CI.

**D11. Static bearer token, stored in Keychain.**
Real authentication is out of scope, but credentials still go through Keychain, never
`UserDefaults`, so the pattern is right when real auth arrives.

**D12. Swift 6 strict concurrency from day one.**
Actors for `FeedStore`, `Outbox` and `ReconnectingSocket`, and `Sendable` DTOs.
Retrofitting strict concurrency later is painful, and it signals that the code is current.

**D13. Two CI jobs.**
A Linux job (fast and cheap) runs Core, API, Simulator and Server tests on every push. A
macOS job (slow, limited minutes) runs on PRs and `main`: XcodeGen, then build, unit,
snapshot and UI tests, then exports screenshots and a simulator video as artifacts. These
artifacts replace Xcode Previews.

**D14. Snapshot tests (swift-snapshot-testing) on the macOS runner.**
They catch UI regressions without an interactive Mac, and their reference images double
as README screenshots.

---

## 6. Development loop without a Mac

1. Edit in VS Code (Swift extension + sourcekit-lsp; Core resolves fully).
2. `scripts/dev.sh test`: runs `swift test` inside the `swift:6.3` Docker image. Docker Desktop
   must be started manually first.
3. `scripts/dev.sh server`: runs the simulator server in Docker at `localhost:8080`.
4. Push the branch, then download screenshots and video from the `ci-ios` run artifacts.
5. Rent a cloud Mac (MacinCloud, Scaleway, etc.) for a few hours only when interactive UI
   debugging is unavoidable.

---

## 7. Step-by-step plan

### M0: Repository and tooling
- [x] 0.1 `git init`, `.gitignore` (Swift, Xcode, DerivedData, `.build`), MIT licence, README skeleton
- [x] 0.2 `Package.swift` with empty `FireWatchCore` and one passing test; Swift 6 language mode
- [x] 0.3 Docker dev setup (`docker/Dockerfile.dev`) and `scripts/dev.sh` commands `test`, `build`, `shell`, `server` (no `make` on this machine)
- [x] 0.4 swift-format config and `scripts/dev.sh format` / `lint` commands
- [x] 0.5 `ci-linux.yml`: build, test, warnings-as-errors and format check on push
- [x] 0.6 `docs/architecture.md` with the diagrams from this plan; copy decisions into `docs/decisions/`

### M1: Core domain model
- [x] 1.1 `Coordinate`, `BoundingBox`, haversine distance and bearing (with tests against known city pairs)
- [x] 1.2 `Hotspot` (id, coordinate, temperatureC, confidence, firstSeen, lastSeen, status, history)
- [x] 1.3 `HotspotStatus` state machine with legal transitions and tests for illegal ones
- [x] 1.4 `FirePerimeter` (polygon rings, timestamp) and a point-in-polygon test
- [x] 1.5 `Drone` (position + capped recent track); `SightingReport` (id, coordinate, severity, note, photo reference)
- [x] 1.6 `PriorityRanker`: score = f(temperature, recency, distance), with tests for ordering edge cases

### M2: Fake-data simulator
- [x] 2.1 `SeededRandom` (SplitMix64) with a determinism test
- [x] 2.2 `TerrainGrid`: fuel and slope fields from layered noise; origin, cell size, coordinate↔cell conversion
- [x] 2.3 `FireSpreadModel`: cell states and a wind-biased ignition step, with tests (no spread without fuel, downwind bias)
- [x] 2.4 Perimeter extraction (trace cell boundaries of the burned mask → rings with holes, then smooth)
- [x] 2.5 Residual hotspots: spawn behind the front, exponential cooling, flare-up probability
- [x] 2.6 Drone planner: lawnmower survey pattern; a detection happens only when a drone's footprint covers a hotspot
- [x] 2.7 `FeedEvent` vocabulary and `FireState` reducer in Core (observations create/update hotspots; detection-driven flare-up rule)
- [x] 2.8 `Scenario` timeline: precomputed fire, hotspots, drone passes and perimeters; determinism and golden-summary tests
- [x] 2.9 `SimulatedWorld`: scenario plus crew interventions (an extinguished hotspot reads cool until its scheduled flare-up); `events(in:)`
- [x] 2.10 Presets: default (Manavgat) and a 2,000-hotspot stress scenario

### M3: API contract
- [x] 3.1 `FireWatchAPI` module with GeoJSON `Geometry`/`Feature`/`FeatureCollection` Codable types and round-trip tests
- [x] 3.2 DTOs for Snapshot, Hotspot, Perimeter, Drone, Report, Command, Event batch and Error; shared JSON coding (ISO 8601 with milliseconds)
- [x] 3.3 Domain↔DTO mappers in `FireWatchAPI` (Core stays free of wire concerns); `schemaVersion` with a test that rejects unknown versions
- [x] 3.4 `fwgen` CLI: `fwgen --preset default --minutes 180 --out fixtures/` exports snapshots and events as API JSON
- [x] 3.5 `docs/api.md`: endpoints, event types and example payloads (generated with `fwgen`)

### M4: Simulator server (Vapor)
- [x] 4.1 Vapor target, `/health`, and a Docker image plus `docker-compose.yml`
- [x] 4.2 `ReplayClock` actor (start, pause, speed, reset) and control endpoints (FR-S3)
- [x] 4.3 REST: `GET /v1/snapshot`, `/v1/hotspots?bbox=`, `/v1/perimeters`, `/v1/drones` (FR-S1)
- [x] 4.4 WebSocket `/v1/stream`: pushes scenario events as the clock advances (FR-S2)
- [x] 4.5 `POST /v1/reports`, `POST /v1/hotspots/:id/status`; idempotency by client UUID (FR-S4)
- [x] 4.6 Fault-injection middleware: latency, drop rate, `/v1/control/disconnect` (FR-S5)
- [x] 4.7 Bearer-token middleware (D11) and XCTVapor tests for every endpoint

### M5: Core client layer
- [x] 5.1 Extract `ReplaySession` and `ReplayClock` into the Simulator, so the server and the on-device demo share one implementation
- [x] 5.2 `DetectionFeed` and `CommandSink` protocols plus `FixtureFeed` in Core; `SimulatedFeed` (in-process `ReplaySession` on a clock) in the Simulator
- [x] 5.3 `FireWatchClient` module: `HTTPTransport` protocol, a `URLSession` implementation and a fake; `APIClient` with typed errors
- [x] 5.4 `ReconnectingSocket` with backoff and jitter (Core); `URLSessionWebSocketTask` adapter (Client); tests with fakes (NFR-4)
- [x] 5.5 `ServerFeed` (snapshot, then stream; fresh snapshot after every reconnect) and `ServerCommandSink`
- [x] 5.6 `FeedStore` actor: applies feed updates, replays pending commands over server state (D9), publishes an `AsyncStream` of state
- [x] 5.7 `Outbox` actor + `OutboxStore` protocol (in-memory impl): enqueue, flush in order, retry with backoff, drop rejected
- [x] 5.8 `AlertEngine`: alerts for new hotspots or flare-ups within radius *R* of the user (FR-8 logic)
- [x] 5.9 Coverage report in CI, failing below 80 % for Core (NFR-9)

### M6: App skeleton and the macOS pipeline (do this before writing any real UI)
- [x] 6.1 `App/project.yml` (XcodeGen), linking the local package; iOS 17 deployment target
- [x] 6.2 Minimal `FireWatchFieldApp` with a `TabView` (Map / List / Report / Settings), all placeholders
- [x] 6.3 `ci-ios.yml`: install XcodeGen, generate, build for the iPhone simulator
- [x] 6.4 One UI test that launches the app and attaches a screenshot; CI exports `.xcresult` attachments as an artifact
- [x] 6.5 Simulator screen recording (`xcrun simctl io booted recordVideo`) during UI tests, uploaded as an artifact
- [ ] 6.6 App-wide dependency container (`AppEnvironment`) choosing `SimulatedFeed` or `ServerFeed`

### M7: Map (FR-1, FR-2, FR-3)
- [ ] 7.1 `MapScreen` with SwiftUI `Map`, centred on the scenario bounding box
- [ ] 7.2 Hotspot annotations: severity colour **plus** symbol (NFR-6), with VoiceOver labels
- [ ] 7.3 Clustering at low zoom (grid clustering computed in Core, so it's tested on Linux)
- [ ] 7.4 Perimeter `MapPolygon` overlay and a timeline scrubber over perimeter history
- [ ] 7.5 Drone annotations with heading and a recent-track polyline
- [ ] 7.6 User location ("when in use" permission, purpose string) and a recentre button

### M8: Hotspot list, detail and workflow (FR-4, FR-5, FR-6)
- [ ] 8.1 `HotspotListScreen` sorted by `PriorityRanker`, with status and severity filters
- [ ] 8.2 `HotspotDetailScreen`: stats, temperature sparkline (Swift Charts), distance and bearing
- [ ] 8.3 "Open in Maps" walking directions
- [ ] 8.4 Status actions that follow the state machine, enqueue to the Outbox and update optimistically
- [ ] 8.5 UI test: assign → extinguish → verify flow, with screenshots

### M9: Live alerts (FR-8)
- [ ] 9.1 Connection-status indicator (live / reconnecting / offline)
- [ ] 9.2 In-app alert banner driven by `AlertEngine`
- [ ] 9.3 Local notifications (permission flow; tapping one deep-links to the hotspot)
- [ ] 9.4 `BGAppRefreshTask` for a background snapshot refresh (NFR-5)

### M10: Offline and persistence (FR-9, NFR-3)
- [ ] 10.1 SwiftData models and a `HotspotStore` adapter (snapshot cache)
- [ ] 10.2 SwiftData `OutboxStore` adapter
- [ ] 10.3 Launch from cache first, then refresh (NFR-2 launch target)
- [ ] 10.4 Offline banner showing data age, and a badge with the queued-action count
- [ ] 10.5 UI test: go offline (server fault injection), make changes, kill and relaunch, reconnect, check everything synced

### M11: Report a sighting (FR-7)
- [ ] 11.1 Report form: severity, note, current location (editable pin)
- [ ] 11.2 Photo from `PhotosPicker` (the simulator has no camera) and the camera on a real device; strip EXIF except GPS
- [ ] 11.3 Submit through the Outbox; show the report on the map as "pending" until acknowledged

### M12: Settings, demo mode and localisation (FR-10, FR-11, NFR-7)
- [ ] 12.1 Settings screen: data source, server URL, alert radius, units
- [ ] 12.2 Token entry stored in Keychain (D11)
- [ ] 12.3 Demo mode as the first-launch default, with a short onboarding card
- [ ] 12.4 String Catalog with a full Turkish translation; units formatted with `Measurement`

### M13: Quality pass (NFR-2, NFR-6)
- [ ] 13.1 Performance tests: launch metric, plus map scrolling with the 2,000-hotspot fixture
- [ ] 13.2 `performAccessibilityAudit()` in UI tests; fix the findings
- [ ] 13.3 Dynamic Type AX5 and dark/high-contrast snapshot tests
- [ ] 13.4 Snapshot test suite in both EN and TR (D14)

### M14: Presentation
- [ ] 14.1 README: one-paragraph pitch, GIF (from the CI video), screenshots, architecture diagram
- [ ] 14.2 README "Design decisions" section linking to `docs/decisions/`
- [ ] 14.3 "Run it yourself" instructions: demo mode with no server; server with `docker compose up`
- [ ] 14.4 Tag `v1.0.0` and write release notes

### M15 (optional): TestFlight
- [ ] 15.1 Apple Developer account; App Store Connect API key stored in GitHub secrets
- [ ] 15.2 fastlane `match` signing, and a `beta` lane run from a manual workflow
- [ ] 15.3 TestFlight public link in the README

### M16 (later): Real FireWatch data
- [ ] 16.1 `FireWatchFeed` adapter from the drone pipeline's output to `FireWatchAPI` DTOs
- [ ] 16.2 Run the app against recorded real flight data
- [ ] 16.3 (Maybe) A Jetpack Compose Android client against the same server
