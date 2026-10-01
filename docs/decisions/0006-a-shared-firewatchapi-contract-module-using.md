# D6. A shared `FireWatchAPI` contract module, using GeoJSON for geometry

Status: accepted (2026-10-01)

*Alternative:* separate DTOs on the client and the server.
*Why:* one Codable definition, imported by both sides, makes contract drift a compile
error. GeoJSON is what GIS tools and the real drone pipeline will produce. Paths are
versioned (`/v1`) and every payload carries `schemaVersion`.
