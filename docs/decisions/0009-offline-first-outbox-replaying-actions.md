# D9. Offline-first with an outbox; conflicts resolved by replaying workflow actions

Status: accepted (2026-10-01), revised during M1 review: replaced "most advanced status wins".

Writes go to a persistent outbox (client UUID, attempt count, next retry time) and are
flushed when connectivity returns. Crews send *actions* (`assign`, `extinguish`, …), not
target statuses. *Conflict policy:* the server is authoritative for detections
(temperature, position) and applies each queued action only if the workflow state
machine allows it from the hotspot's **current** status, rejecting it otherwise. On the
device, the displayed state is the server state with still-pending actions replayed on
top (an optimistic rebase); a rejected action is dropped and the user is told.
*Example:* a crew marks a hotspot `verifyCold` offline, but a drone saw it flare up in the
meantime. `verifyCold` isn't legal from `flaredUp`, so it's rejected, and the crew sees the
flare-up instead of a false "cold".
*Alternative considered:* "most advanced status wins". It breaks on flare-ups (a cycle,
not a line) and on unassign (a legitimate step backwards).
*Why:* this is the real need for crews out of signal, and a strong interview topic.
