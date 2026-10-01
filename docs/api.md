# FireWatch Field API — v1

The contract between the simulator server and the app. It is defined once, in the
`FireWatchAPI` Swift module, and imported by both sides (design decision D6), so this
document describes the code rather than the other way round.

- **Base path:** `/v1`. A breaking change gets a new path and a new `schemaVersion`.
- **Format:** JSON, UTF-8, keys sorted. Dates are ISO 8601 UTC with milliseconds
  (`2026-08-01T10:29:40.000Z`); dates without fractional seconds are accepted too.
- **Positions:** GeoJSON order, `[longitude, latitude]`. Perimeters are GeoJSON
  `Feature`s with `MultiPolygon` geometry and closed rings (RFC 7946).
- **Auth:** every `/v1` request needs `Authorization: Bearer <token>`. The simulator's
  token is set with the `FIREWATCH_TOKEN` environment variable.
- **Versioning:** snapshots and event batches carry `schemaVersion`. Clients reject
  versions they don't know, and skip event `type`s they don't know.
- **Enumerations** travel as strings:
  - status: `new`, `assigned`, `extinguished`, `verifiedCold`, `flaredUp`
  - action: `assign`, `unassign`, `extinguish`, `verifyCold`, `flareUp`
  - severity: `low`, `moderate`, `high`, `extreme`

Example payloads below come from `fwgen --preset manavgat --minutes 120` with long
coordinate lists shortened. Run it yourself for complete files:

```bash
scripts/dev.sh shell
swift run fwgen --minutes 120 --out fixtures
```

## Endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/health` | | `200 ok` (no auth) |
| `GET` | `/v1/snapshot` | | `SnapshotDTO` |
| `GET` | `/v1/hotspots?bbox=minLon,minLat,maxLon,maxLat` | | `[HotspotDTO]` |
| `GET` | `/v1/perimeters` | | `PerimeterHistoryDTO` (GeoJSON `FeatureCollection`) |
| `GET` | `/v1/drones` | | `[DroneDTO]` |
| `WS` | `/v1/stream` | | `EventBatchDTO` messages |
| `POST` | `/v1/commands` | `CommandDTO` | `ReceiptDTO`, or an error |
| `POST` | `/v1/reports` | `ReportDTO` | `ReceiptDTO`, or an error |
| `GET` | `/v1/control` | | `ReplayStatusDTO` |
| `POST` | `/v1/control` | `ReplayControlDTO` | `ReplayStatusDTO` |
| `POST` | `/v1/control/faults` | `FaultsDTO` | `FaultsDTO` |
| `POST` | `/v1/control/disconnect` | | `204`, and every stream is closed |

The `/v1/control` endpoints exist only on the simulator. They drive the replay and inject
faults, so the app's offline behaviour can be demonstrated (FR-S3, FR-S5).

### Errors

Every 4xx and 5xx response has an `ErrorDTO` body:

```json
{ "code": "notAllowed", "message": "verifyCold is not allowed from flaredUp" }
```

| Status | `code` | When |
|---|---|---|
| 400 | `invalidPayload` | The body doesn't decode, or holds an unknown enumeration value |
| 401 | `unauthorized` | Missing or wrong bearer token |
| 404 | `unknownHotspot` | The command names a hotspot the server hasn't detected |
| 409 | `notAllowed` | The action isn't legal from the hotspot's current status |
| 503 | `injectedFault` | Dropped on purpose by fault injection |

## Snapshot

`GET /v1/snapshot` returns everything known now: every detected hotspot with its recent
readings, every drone with its recent track, and the latest perimeter. A client loads
this first, then applies stream events on top.

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-08-01T12:00:00.000Z",
  "hotspots": [
    {
      "id": "hs-r047c034",
      "location": [31.4555363, 36.8245663],
      "confidence": 0.84,
      "firstSeen": "2026-08-01T10:29:40.000Z",
      "status": "new",
      "flareUps": 0,
      "readings": [
        { "time": "2026-08-01T10:29:40.000Z", "celsius": 531.8 },
        { "time": "2026-08-01T11:09:20.000Z", "celsius": 318.2 }
      ]
    }
  ],
  "drones": [
    {
      "id": "drone-1",
      "name": "Kartal-1",
      "track": [
        {
          "time": "2026-08-01T11:59:40.000Z",
          "location": [31.452023, 36.8203323],
          "headingDegrees": 0,
          "altitudeMetres": 120,
          "battery": 0.4
        }
      ]
    }
  ],
  "perimeter": {
    "type": "Feature",
    "geometry": { "type": "MultiPolygon", "coordinates": [[[[31.4553937, 36.824323], "…", [31.4553937, 36.824323]]]] },
    "properties": { "time": "2026-08-01T12:00:00.000Z", "areaHectares": 128.4 }
  }
}
```

`readings` keeps the newest 48; `track` keeps the newest 30 positions. `firstSeen` can
be older than the oldest kept reading.

## Event stream

`/v1/stream` is a WebSocket. The server sends an `EventBatchDTO` each time the replay
clock ticks, holding every event since the previous batch, in time order:

```json
{ "schemaVersion": 1, "events": [ { "type": "…", "data": { … } } ] }
```

| `type` | `data` | Meaning |
|---|---|---|
| `hotspotObserved` | `ObservationDTO` | A drone measured a hotspot. The first observation of an ID means it was just detected. |
| `hotspotCommandApplied` | `CommandDTO` | A crew command was accepted (from any device, including this one). |
| `perimeterUpdated` | `PerimeterDTO` | A new fire outline, every 5 scenario minutes. |
| `droneMoved` | `DroneUpdateDTO` | A drone's position, every 20 scenario seconds. |

```json
{ "type": "hotspotObserved",
  "data": { "hotspotID": "hs-r047c034", "location": [31.4555363, 36.8245663], "time": "2026-08-01T10:29:40.000Z",
            "celsius": 531.8, "confidence": 0.91, "droneID": "drone-1" } }

{ "type": "hotspotCommandApplied",
  "data": { "id": "6f1c…", "hotspotID": "hs-r047c034", "action": "extinguish", "issuedAt": "2026-08-01T11:15:02.120Z" } }

{ "type": "droneMoved",
  "data": { "droneID": "drone-2", "name": "Şahin-2",
            "position": { "time": "2026-08-01T10:00:00.000Z", "location": [31.4610115, 36.8041445],
                          "headingDegrees": 0, "altitudeMetres": 120, "battery": 1 } } }
```

A hot `hotspotObserved` (150 °C or more) on an `extinguished` or `verifiedCold` hotspot
means it **flared up**: clients apply the `flareUp` action themselves. Server and app run
the same reducer (`FireState`), so they always agree.

After a reconnect, a client fetches a fresh snapshot rather than trying to catch up on
missed events.

Batches that carry a perimeter can be a few hundred kilobytes, so clients must accept
WebSocket messages of at least 1 MB (`URLSessionWebSocketTask`'s default).

## Commands

Crews change a hotspot's status by sending **actions**, not statuses (D9). The client
generates the `id`; sending the same command again is safe and returns `duplicate`.

```http
POST /v1/commands
{ "id": "6f1c…", "hotspotID": "hs-r047c034", "action": "extinguish", "issuedAt": "2026-08-01T11:15:02.120Z" }

200 OK
{ "id": "6f1c…", "outcome": "applied" }
```

The server checks the action against the hotspot's **current** status. A command queued
offline can therefore be refused if things changed meanwhile, for example `verifyCold`
after a drone saw the spot flare up (`409 notAllowed`). The client then drops it and
shows the user the current state.

Legal actions by status:

| Status | Allowed actions |
|---|---|
| `new` | `assign`, `extinguish` |
| `assigned` | `unassign`, `extinguish` |
| `extinguished` | `verifyCold`, `flareUp` |
| `verifiedCold` | `flareUp` |
| `flaredUp` | `assign`, `extinguish` |

`flareUp` is normally inferred from observations, as above, rather than sent by crews.

## Sighting reports

```http
POST /v1/reports
{ "id": "a93e…", "createdAt": "2026-08-01T11:20:00.000Z", "location": [31.4612, 36.8301],
  "severity": "high", "note": "Smoke behind the ridge", "photoJPEG": "/9j/4AAQ…" }

200 OK
{ "id": "a93e…", "outcome": "applied" }
```

`photoJPEG` is optional, base64-encoded in JSON.

## Replay control (simulator only)

```http
GET /v1/control
200 OK
{ "preset": "manavgat", "state": "running", "speed": 60, "scenarioMinute": 42.5, "scenarioMinutes": 240 }

POST /v1/control
{ "action": "start", "speed": 120 }            // or "pause", or "reset" (optionally with "preset")
```

`speed` is scenario seconds per real second, from 1 to 600. `reset` restarts the scenario
at the configured start minute (`FIREWATCH_START_MINUTE`, 60 by default), clears every
crew command, and closes every stream so clients resync. A finished replay reports
`"state": "finished"`.

```http
POST /v1/control/faults
{ "latencyMilliseconds": 800, "dropRate": 0.3 }  // 30 % of requests fail with 503 injectedFault
```
