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

## Repository layout

| Path | What |
|---|---|
| `Sources/FireWatchCore` | Domain model, geo math, sync engine. Builds on Linux and iOS. |
| `App/` | SwiftUI app (project generated with XcodeGen). |
| `docs/` | [Architecture](docs/architecture.md) and [design decisions](docs/decisions/README.md). |
| `scripts/dev.sh` | Dev tasks (`test`, `lint`, `format`) run in a Linux Swift container. |

## License

MIT
