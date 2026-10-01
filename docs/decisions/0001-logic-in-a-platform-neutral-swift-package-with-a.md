# D1. Logic in a platform-neutral Swift package, with a thin UI layer

Status: accepted (2026-10-01)

*Alternative:* everything in the app target.
*Why:* without a Mac, the only code you can iterate on quickly is code that builds on
Linux. It's also good architecture: domain logic stays testable without a simulator, and
the same Core can later run inside the real FireWatch backend (NFR-11).
