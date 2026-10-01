# D4. Deterministic, seeded fake data instead of random or hand-written JSON

Status: accepted (2026-10-01)

*Alternative:* a few static JSON files.
*Why:* a believable demo needs fire that *moves*: a spreading front, residual hotspots
that cool, and occasional flare-ups. Seeding (SplitMix64, because Foundation's RNG
can't be seeded) makes tests and screenshots reproducible (NFR-12). One generator feeds
the server, the bundled fixtures and the tests, so they never disagree.
