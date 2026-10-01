# Architecture

FireWatch Field is split so that almost all logic builds and tests on Linux. Only the
SwiftUI layer needs macOS, and that is built and tested on GitHub Actions macOS runners.
See [decisions/](decisions/README.md) for the reasoning behind each choice.

## Modules

| Module | Purpose | Platforms |
|---|---|---|
| `FireWatchCore` | Domain model, geo math, hotspot workflow, `FireState` reducer, priority ranking, alerts; the client engine: `DetectionFeed`/`CommandSink` protocols, `FeedStore`, `Outbox`, `ReconnectingSocket` | Linux, iOS |
| `FireWatchAPI` | Versioned Codable wire contract and GeoJSON types, shared by server and app | Linux, iOS |
| `FireWatchSimulator` | Seeded wildfire scenario, `ReplaySession` (shared by server and demo mode) and `SimulatedFeed` | Linux, iOS |
| `FireWatchClient` | `APIClient` over an `HTTPTransport`, `ServerFeed`, `ServerCommandSink`, `URLSessionWebSocketTask` adapter | Linux, iOS |
| `FireWatchServer` (`Server/`) | Vapor server around a `ReplaySession`: REST, WebSocket, replay control, fault injection, auth | Linux (Docker) |
| `fwgen` | CLI that exports scenarios as API JSON | Linux |
| `App/FireWatchField` | SwiftUI app: screens, view models, SwiftData persistence adapters | iOS |

Dependency direction: `Client → API → Core`, `Simulator → Core`, `App → Client, Simulator`,
`Server → API, Simulator`. Nothing outside `App/` imports Apple-only frameworks (UIKit,
SwiftUI, MapKit, CoreLocation, SwiftData).

## Data flow

```
FireWatchSimulator ─► FireWatchServer ─REST/WS─► ServerFeed ─────┐
        │                                                        ├─► FeedStore (actor) ─► ViewModels ─► SwiftUI
        └─── in-process, demo mode ─────────────► SimulatedFeed ─┘      │
                                                                     Outbox (actor) ──► server (writes)
                                                                        │
                                                                     Persistence (SwiftData, app layer)
```

- **Reads:** a `DetectionFeed` (the on-device simulator in demo mode, the server otherwise,
  and the real FireWatch pipeline later) sends a snapshot, then event batches, and a fresh
  snapshot after every reconnect. `FeedStore` applies them with the shared `FireState`
  reducer and publishes `FieldState` as an `AsyncStream`, which view models observe.
- **Writes:** status changes and sighting reports go to the `Outbox` first, each with a
  client-generated ID, and are persisted so they survive a relaunch. They are sent in
  order when possible, retried with jittered backoff, and dropped with a message to the user
  if rejected. The server treats the ID as an idempotency key.
- **Conflicts:** the server is authoritative for detection data. Crews send workflow actions;
  the server applies each only if it is still legal from the current status. On the device,
  pending commands are replayed over the latest feed state (D9).
- **Time:** everything relative ("seen 5 minutes ago", ranking recency) uses the feed's time
  (`FieldState.asOf`), which is scenario time with the simulator, never the device clock.

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
| Local (Windows) | Everything below `App/` | `scripts/dev.sh check` in the `swift:6.3` container |
| CI: `ci-linux` | Same, plus format lint and a Core coverage gate (80 %), on every push | `swift:6.3` container jobs |
| CI: `ci-ios` (from M6) | XcodeGen, app build, unit, snapshot and UI tests, screenshots and video | macOS runner, on PRs and `main` |

The Linux toolchain's libcurl has no WebSocket support, so `URLSessionWebSocketTask` can't
run there. Linux tests inject a WebSocketKit-based `SocketConnector` instead; the
`URLSession` adapter runs on iOS.
