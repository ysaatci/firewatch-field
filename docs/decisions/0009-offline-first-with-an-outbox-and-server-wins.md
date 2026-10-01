# D9. Offline-first with an outbox, and server-wins merge with a field-level exception

Status: accepted (2026-10-01)

Writes go to a persistent outbox (client UUID, attempt count, next retry time) and are
flushed when connectivity returns. *Conflict policy:* the server is authoritative for
detections (temperature, position). For status, the **most advanced workflow state
wins**, so an `extinguished` from the field is never overwritten by a stale `assigned`.
*Why:* this is the real need for crews out of signal, and a strong interview topic.
