# Architecture

FireWatch Field is split so that almost all logic builds and tests on Linux. Only the
SwiftUI layer needs macOS, and that is built and tested on GitHub Actions macOS runners.
See [decisions/](decisions/README.md) for the reasoning behind each choice.

## Modules

| Module | Purpose | Platforms |
|---|---|---|
| `FireWatchCore` | Domain model, geo math, priority ranking, sync engine (feed store, outbox, reconnecting socket), data-source protocols | Linux, iOS |
| `FireWatchAPI` | Versioned Codable wire contract and GeoJSON types, shared by server and app | Linux, iOS |
| `FireWatchSimulator` | Seeded fire-spread scenario generator (the fake data source) | Linux, iOS |
| `FireWatchServer` | Vapor server: REST, WebSocket, replay control, fault injection | Linux (Docker) |
| `fwgen` | CLI that exports scenarios as JSON fixtures for the app bundle and tests | Linux |
| `App/FireWatchField` | SwiftUI app: screens, view models, SwiftData persistence adapters | iOS |

Dependency direction: `App → Core → API`; `Server → Simulator → Core`. Core and API
never import Apple-only frameworks (UIKit, SwiftUI, MapKit, CoreLocation, SwiftData).

## Data flow

```
FireWatchSimulator ──► FireWatchServer ──REST/WS──► ServerFeed ┐
        │                                                    ├─► FeedStore (actor) ─► ViewModels ─► SwiftUI
        └──── fwgen ──► bundled JSON fixtures ─► FixtureFeed ┘           │
                                                                 Outbox (actor) ──► server (writes)
                                                                         │
                                                                 Persistence (SwiftData, app layer)
```

- **Reads:** a `DetectionFeed` (fixtures in demo mode, the server otherwise, and the real
  FireWatch pipeline later) produces events. `FeedStore` applies them and publishes state
  as an `AsyncStream`, which view models observe.
- **Writes:** status changes and sighting reports go to the `Outbox` first, each with a
  client-generated UUID. They are flushed when the connection is up and retried with
  backoff. The server treats the UUID as an idempotency key.
- **Conflicts:** the server is authoritative for detection data. Crews send workflow actions;
  the server applies each only if it is still legal from the current status (see D9).

## Hotspot workflow

Status changes happen through actions, validated by `HotspotWorkflow`:

```
new ──assign──► assigned ──extinguish──► extinguished ──verifyCold──► verifiedCold
 ▲                │  ▲                       │                            │
 └────unassign────┘  └──assign── flaredUp ◄──┴────────── flareUp ─────────┘
```

`extinguish` is also allowed straight from `new` or `flaredUp`. `flareUp` comes from
detection (a drone measures the spot hot again), never from crews.

## Build and test

| Where | What runs | How |
|---|---|---|
| Local (Windows) | Core, API, Simulator, Server | `scripts/dev.sh test` in the `swift:6.3` container |
| CI: `ci-linux` | Same, plus format lint, on every push | `swift:6.3` container job |
| CI: `ci-ios` (from M6) | XcodeGen, app build, unit, snapshot and UI tests, screenshots and video | macOS runner, on PRs and `main` |
