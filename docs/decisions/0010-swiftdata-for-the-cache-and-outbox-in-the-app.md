# D10. SwiftData for the cache and outbox in the app; storage protocols in Core

Status: accepted (2026-10-01)

*Alternative:* GRDB/SQLite inside Core, which would also be testable on Linux.
*Why:* SwiftData is the modern Apple stack recruiters look for. Core defines
`HotspotStore` and `OutboxStore` protocols with in-memory implementations, so the sync
*logic* is fully tested on Linux. Only the thin SwiftData adapter is tested on macOS CI.
