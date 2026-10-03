# DELETE D2-A1: local deletion protocol

Local-only change. D1 remains immutable; no SQL migration or remote action.

## Representation and compatibility

SQLite schema stays at version 1. `records.pending` schedules transport, not
terminality. `_sync.tombstone` remains the operational hide/write barrier for
compatibility. `_sync.deletionState` distinguishes new `pending`, `conflict`,
and `confirmed` deletes. `SyncMetadata.deletionState` exposes that distinction;
`AppDatabase.deletionState` additionally reads the legacy SQL pending flag.

Existing ACKs and ledger merges persist both `deletedAt` and
`remoteOperationId`: they are confirmed regardless of lifecycle flag.
DELETE C `operation=cancel/localCancellation=true` remains a protected local
cancellation, not a remote ACK. Legacy DELETE operations with SQL pending=1,
owner, operation ID, positive revision and no ACK/cancellation evidence are
unacknowledged intents. A lost remote response remains such an intent until
positive terminal evidence is received; it never authorizes restoration.
Unknown/incomplete metadata remains `legacyUnknown`, hidden and protected;
there is no blanket conversion of old tombstones or destructive migration.

## Transitions

- ACTIVE -> pending: existing markDeleted, stable operation ID/revision/owner.
- pending -> confirmed: validated soft-delete response or owner-scoped ledger.
- pending -> conflict: only explicit P0001/SYNC_PADDOCK_OCCUPIED for paddocks;
  snapshot compare, owner, identity, operation, revision and pending checked.
- conflict -> confirmed: authoritative ledger always wins.
- conflict -> active projection: only reconcileRejectedPaddockDelete, with an
  unchanged conflict snapshot and positive active server data. Caller must fetch
  authenticated owner-filtered data after rejection and serialize it to local
  format, including id, user_id and explicit deleted_at=null. This primitive
  does not itself fetch or authenticate network data and has no UI caller yet.

Ordinary putRecord and replaceRecordIfUnchanged cannot restore hidden records.
CAS also cannot strip terminal ACK evidence or discard rejection metadata.
Reconciliation preserves the rejected operation; later edits/refreshes retain
its audit context. Creating another delete requires future explicit conflict
resolution: this phase does not silently allocate a new identity.

## Sync and session safety

Only the known occupied rejection leaves the retry queue. Transient failures
retain pending. Authorization errors are classified separately; existing session
handling remains. SYNC_ENTITY_DELETED is a reason to fetch evidence, never an ACK.
The remote user and local owner are checked before persisting a rejection.
The normal tombstone pull follows rejection and may immediately confirm deletion.

Conflicts (including reconciled projections retaining unresolved intent) block
logout and clearAll so their pending=0 cannot silently discard them. Resolution
UX and explicit conflict dismissal are deferred. Authoritative terminal merge
clears the unresolved rejection marker.

## Scope and tests

No MOVE RPC, paddock delete UI, D1/E changes or remote calls. Focused tests cover
restart, legacy evidence, guarded reconciliation, stale ACK/rejection, account
changes, terminal precedence, durable retry suppression and session cleanup.
Existing DELETE A/B/C, outbox and logout suites remain required regressions.
