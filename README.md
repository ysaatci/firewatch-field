# FireWatch Field

[![ci-linux](https://github.com/ysaatci/firewatch-field/actions/workflows/ci-linux.yml/badge.svg)](https://github.com/ysaatci/firewatch-field/actions/workflows/ci-linux.yml)

An iOS app for wildfire ground crews. It shows drone-detected hotspots and the live
fire perimeter, lets crews claim and close out hotspots during mop-up, and keeps
working with no signal.

> **Status:** early development. See [plan.md](plan.md) for requirements, design
> decisions and the step-by-step roadmap.

Until the FireWatch drone pipeline is ready, data comes from a deterministic,
seeded fire-spread simulator written in Swift. It uses the same API contract the
real pipeline will use.

## Run the simulator server

Needs Docker. From the repository root:

```bash
docker compose up --build
```

It serves a replaying wildfire at `http://localhost:8080` with the token `dev-token`:

```bash
curl -H "Authorization: Bearer dev-token" http://localhost:8080/v1/snapshot
```

Speed, preset and start time are set in [docker-compose.yml](docker-compose.yml); the
endpoints are described in [docs/api.md](docs/api.md).

## Repository layout

| Path | What |
|---|---|
| `Sources/FireWatchCore` | Domain model, geo math, hotspot workflow, event reducer. Builds on Linux and iOS. |
| `Sources/FireWatchSimulator` | Seeded wildfire simulator: terrain, fire spread, hotspots, drone survey. |
| `Sources/FireWatchAPI` | Versioned wire contract (DTOs, GeoJSON) shared by server and app. |
| `Sources/fwgen` | CLI that exports simulated scenarios as API JSON. |
| `Server/` | Vapor simulator server (separate package): REST, WebSocket stream, replay control, fault injection. |
| `App/` | SwiftUI app (project generated with XcodeGen). |
| `docs/` | [Architecture](docs/architecture.md), [API](docs/api.md) and [design decisions](docs/decisions/README.md). |
| `scripts/dev.sh` | Dev tasks (`check`, `test`, `lint`, `format`) run in a Linux Swift container. |

## License

MIT
