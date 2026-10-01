# D15. Idempotent reducer, and a fresh snapshot after every reconnect

Status: accepted (2026-10-01), added during M5.

After any (re)connect, the client opens the event stream first and then fetches a
snapshot, while stream messages wait in a buffer. Buffered events older than the snapshot
are dropped. The `FireState` reducer is idempotent, so any duplicate that slips through
(an event both in the snapshot and in the stream) changes nothing: readings, drone
positions and perimeters must be strictly newer than the latest to count, and no workflow
action is legal twice in a row.

*Alternative:* sequence numbers on every event and replaying missed ranges after a
reconnect. More precise, but it needs a server-side event log and gap detection.

*Why:* snapshots are small and the simulator (and the real pipeline) can always produce
one, so "resnapshot on reconnect" is simple and always correct. Idempotence turns ordering
races into non-issues instead of bugs to hunt.
