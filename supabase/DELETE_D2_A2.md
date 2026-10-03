# DELETE D2-A2 — explicit paddock edit intent

Local implementation only. D1 is unchanged. No remote SQL/deploy or DELETE E.
D2-A1 remains in place; this is not atomic MOVE adoption.

## Mutation-source audit

| Source | Classification / fields | Independent publication | Pending MOVE interaction |
|---|---|---|---|
| PaddockForm, new | CREATE, complete domain snapshot | Yes, full existing upsert | Must be published before future MOVE projection API |
| ConfigureFarm / LoadDemoData | CREATE, complete snapshots | Yes | No MOVE during initial setup; cleanup guards still apply |
| PaddockForm, edit | USER_EDIT_PATCH, explicitly touched controls only | Yes, partial update | Nonoperational patches wait; operational patches conflict |
| Rest dialog | USER_EDIT_PATCH, requiredRestDays + explicit Descansando status | Yes, partial update | Conflicts while MOVE projection owns operational state |
| Reorder action | SYSTEM/ROTATION_UPDATE initiated by user, rotationOrder only | Yes, ordered patches | Waits behind MOVE projection |
| AnimalViewModel.moveMany | Existing legacy movement transaction: origin/destination status, grazingStartDate, plannedGrazingDays, lastGrazingEndDate | Still legacy full write until D2 MOVE adoption | Full write refused when unresolved new patch/projection exists; transaction rolls back |
| New projectPaddockMove API | MOVE_PROJECTION, operational fields only, durable movement ID | Never | Explicit completion after future validated RPC required |
| PaddockRepository.getAll remote fallback | REMOTE_MERGE, full downloaded fields | No | Overlay pending patches and local MOVE fields; retain marker |
| calculate_paddock_rotation / operational status calculator | Read-only | No writes | Unchanged |
| Generic markDeleted / ACK / ledger | DELETE_INTENT / terminal metadata | Existing DELETE RPC | Hidden records reject edits; accepted deletion conflicts patches |
| PaddockRemoteDataSource.upsert | Existing full transport method, not used by new edit path | Legacy/full only | No patch conversion |

Previously PaddockViewModel.save could rest other En uso paddocks even for a
name edit. New edits never call this path. Full ViewModel save now only creates
one paddock; it does not fabricate changes to other paddocks. Explicit status
edits affect only the selected paddock. Repository full save remains available
for onboarding and the unconverted legacy movement transaction.

## Field ownership and UI

name, areaHectares, pastureType, requiredRestDays and rotationOrder are ordinary
user/domain fields. status, grazingStartDate, plannedGrazingDays and
lastGrazingEndDate are shared with operational MOVE: the actual form can edit
them deliberately. onChanged/date-picker callbacks record touched enum fields;
no before/after full-snapshot diff reconstructs intent. Selecting status
explicitly also declares its date/planning normalization fields. Unchanged
carried operational values never enter a name-only patch.

PaddockPatch uses a closed enum and validates values. Map absence means unchanged;
an included null means clear. Dates serialize UTC. Legacy aliases in the UI
projection are cleared too, preventing a null from falling back to an old value.

## Durable storage and ordering

No table/schema migration. `records` collection `paddock_edit_commands` stores
one immutable edit intent: owner in _sync, command ID, entity ID, kind,
baseRevision, explicit fields, createdAt, monotonic order, state
pending/completed/conflict, optional afterMove/error/remoteBaseVersion.
The complete local paddock is only a projection, updated in the same transaction.
Commands survive restart; no coalescing or recreation on retry. The existing
sync coordinator serializes sends and processes patches after domain writes.
Each entity's earlier unresolved command blocks later commands.

A pre-existing full pending CREATE/legacy write is frozen in _basePaddockWrite
before applying a patch to its visible projection. The existing uploader sends
that original full body, ACKs it, then sends patches. It never infers an old
snapshot's edited fields. A later legacy full save is refused while new intents
are unresolved; it cannot replace them or silently reintroduce operational state.

## Future MOVE boundary

projectPaddockMove persists a movement-linked operational marker without pending
full publication. It requires remote-confirmed parent and no pending full write,
prior unresolved patch, or prior MOVE marker. This phase does not solve unpublished
MOVE dependencies or wire the current movement flow to this API.

Ordinary patches after that marker wait. Intentional operational edits become
conflict immediately and retain their values without replacing the MOVE view.
completePaddockMoveProjection is only for a future coordinator after validated
RPC success and authoritative active row retrieval. It checks snapshot, owner,
entity, movement ID and terminal protection, then removes the marker and reapplies
pending ordinary patches. It never infers completion from matching values.

## HTTP and concurrency

The production adapter uses authenticated `.update(explicitFields)` with id,
user_id, deleted_at IS NULL and updated_at equality filters, followed by select
of returned identity. It never adds operational fields from the full entity.
The existing server trigger owns updated_at. Official API:
https://supabase.com/docs/reference/dart/update

Before sending, sync reads and durably binds the existing remote updated_at
version. Retries reuse this version; they do not silently rebase. Zero matched
rows or a wrong response identity produce conflict, not ACK. A lost success
response may therefore require manual reconciliation: this is intentionally
conservative, and is not a server receipt/exactly-once protocol. Conflict UI and
resolution are deferred. Transient errors keep the same command/version pending.
An ACK updates only its command, never overwrites the entity or a newer edit.

## Merge, deletion and session protection

Remote merge overlays pending fields in durable order. Terminal ledger/DELETE
ACK remains stronger and converts unresolved patches to conflicts. Pending or
conflicted DELETE blocks patch creation and ordinary active refresh as in A1.
Unresolved patches/conflicts/MOVE markers protect logout, clearAll and record
removal. Owner checks apply before persistence, publication and ACK.

## Limits retained for subsequent phases

- No sync_move_animal RPC or complete MOVE command here.
- Legacy movement stays legacy. Overlap with unresolved new intents fails closed
  instead of guessing which full snapshot fields can be published.
- New MOVE projection API requires dependencies already resolved.
- Explicit operational edits are not automatically arbitrated against MOVE.
- No conflict dismissal UI, history redesign or physical-device validation.
- Pre-D2 snapshots are never reconstructed into patches.

Additional guards: generic transport rejects a MOVE marker even when called
directly. A local delete cannot bypass an unresolved MOVE marker. Blanket/local
markSynced calls cannot ACK unresolved patch commands. Unverified legacy owners
must obtain positive ownership evidence before using the new edit API; this
phase does not infer ownership from the current session.

## Validation completed

- flutter analyze: no issues.
- 283/283 selected tests PASS, including 34 new A2 tests (25 storage/sync,
  7 mocked HTTP, 2 real form widget tests), 25 A1 tests and DELETE A/B/C,
  remote presence, automatic sync, logout, rotation/calendar and photo suites.
- Formatting and tracked/untracked whitespace checks PASS.
- General expense UI suite was not run; the five known unrelated failures were
  not changed.
- D1 SHA-256 remains
  `7f4ca6fdc45152c21c95564d586469df195872edc15347f242c8cc8cdc712232`.

## Working-tree inventory including retained A1

Modified:
- lib/core/database/app_database.dart
- lib/core/database/sync_metadata.dart
- lib/features/paddocks/data/datasources/paddock_local_datasource.dart
- lib/features/paddocks/data/repositories/paddock_repository_impl.dart
- lib/features/paddocks/domain/repositories/paddock_repository.dart
- lib/features/paddocks/presentation/screens/paddock_screens.dart
- lib/features/paddocks/presentation/viewmodels/paddock_view_model.dart
- lib/features/sync/data/datasources/supabase_sync_remote_datasource.dart
- lib/features/sync/data/datasources/sync_local_datasource.dart
- lib/features/sync/data/datasources/sync_remote_datasource.dart
- lib/features/sync/data/repositories/sync_repository_impl.dart

New:
- lib/core/database/paddock_patch_store.dart
- lib/core/database/sync_failure.dart
- lib/features/paddocks/domain/value_objects/paddock_patch.dart
- supabase/DELETE_D2_A1.md
- supabase/DELETE_D2_A2.md
- test/deletion_state_test.dart
- test/paddock_patch_form_test.dart
- test/paddock_patch_remote_test.dart
- test/paddock_patch_test.dart
