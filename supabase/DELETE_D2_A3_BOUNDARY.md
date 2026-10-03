# D2-A3 — safe Animal publication, without full MOVE

This supersedes the earlier partial/blocked boundary report. Combined descriptive
edit + explicit location selection remains intentionally blocked, per the A3
continuation contract. Full D2 MOVE, D1, DELETE E and remote services are untouched.

## Publication map and field ownership

| Path | Classification / resulting publication |
| --- | --- |
| New AnimalForm -> VM.save -> repository.save -> local.save | CREATE; durable writeKind=create; full initial fields and initial paddockId |
| Existing AnimalForm -> VM.edit -> AnimalEditRepository -> local.edit | USER_EDIT_PATCH; only onChanged/touched fields, no snapshot-derived intent |
| Existing form location dropdown | LOCATION_MOVE; rejects entire save before repository callback |
| Explicit AnimalPatch | code/name/type/breed/sex/birthDate/weight/notes only; rejects location, photo, identity and sync fields |
| Local edit projection | Re-reads latest SQLite row and overlays only intended fields; never copies stale form location |
| Picker / local.edit selectedPhoto | PHOTO_LOCAL; local file plus durable upload job; remote reference retained until upload |
| AnimalPhotoSync checkpoints | Same target, digest, duplicate verification, upload/retry/account checks; no Storage redesign |
| Photo publication for existing animal | PHOTO_REMOTE_REFERENCE_PATCH; HTTP PATCH contains only remote_photo_path, owner/id/active predicates |
| CREATE with photo | Full insert with ignore-duplicates, active owner lookup, then narrow photo reference PATCH; retries never overwrite existing location |
| Generic sync | CREATE/photo only for animals; ambiguous full snapshots quarantined; edit commands handled separately |
| AnimalRemoteDataSource.upsertAnimal | Rejects unsupported full-snapshot publication; callers must use durable intent |
| projectAnimalMove | MOVE_PROJECTION with movement ID/source/destination; local only, no ordinary pending animal write |
| Existing legacy save/saveMove | Retained compatibility input, tagged legacy_full_write on existing row; never automatically publishes location |
| Refresh | REMOTE_MERGE: authoritative location/photo + pending descriptive overlay, or explicit MOVE projection; no new user intent |
| DELETE C / ledger | Terminal precedence; pending edit commands become conflicts on confirmed tombstone; no resurrection |

Identity/creation timestamps are not editable patch fields. Status is carried at
creation, not deliberately edited by the current form. localPhotoPath remains
private device state. remotePhotoPath belongs exclusively to photo publication.
Sync/deletion metadata is not part of the descriptive vocabulary.

## Durable commands and A2 reuse

Animal commands use the same existing records table, `_sync` owner/operation/
revision metadata, pending bit, CAS acknowledgements and ordered processing model
as A2. No destructive SQLite migration or alternate worker architecture.
Animal-specific logic lives in an AppDatabase extension, as does PaddockPatchStore;
the distinct field vocabulary and independent photo lane do not change A2.

`animal_edit_commands` stores entityId, UUID operation identity, baseRevision,
explicit fields, monotonic durable order, createdAt and pending/completed/conflict.
Absent fields and explicit null differ. Remote version is bound once before
sending, exactly as in A2. Retries retain it; zero matched rows or version conflict
become durable conflicts, not automatic rebases. Earlier unresolved commands gate
later commands for the same entity. A successful ACK only completes its command;
it never reapplies old fields over newer intent. It also changes the parent local
revision so a GET begun before ACK cannot restore an obsolete snapshot.

## CREATE and location

A newly persisted animal is explicitly marked CREATE. An edit while CREATE is
pending freezes its original publication body and queues a separate patch.
INSERT uses ignore-duplicates rather than conflict-update, preventing a lost
response/retry from resetting later remote location. The active owner row must
exist before treating creation as successful. Photo references are then applied
narrowly. Terminal conflicts remain server-protected.

`projectAnimalMove` requires an owned active remotely confirmed animal without an
unresolved full write, existing MOVE or legacy conflict. It persists the movement
ID and expected source alongside local destination. Name edits after projection
remain publishable independently. Final D2 must supply the full command, movement
inputs, validated RPC ACK/reconciliation and projection completion lifecycle.

Existing movement use cases have not been converted into MOVE RPC processing.
Their old full saves are legacy compatibility records, not safe new MOVE commands.
An unconfirmed ambiguous parent cannot be uploaded to unblock its movements;
those records remain preserved. Confirmed physical parents still allow existing
historical movement synchronization, including terminal parents (C1 contract).
Do not claim that movement execution has been adopted or validated as final D2.

## Photos and concurrency

Existing-animal photo jobs keep the FOTO durable upload checkpoints. The callback
for the photo lane no longer carries a full Animal snapshot. Its transport sends
only `remote_photo_path`; no updated_at from a stale client, descriptive fields or
paddock_id. A crash after upload retries the same object/reference. The same field
patch is idempotent and commutes with a location change. Concurrent replacements
of the photo itself retain the existing last accepted reference behavior; A3 does
not introduce a cross-device photo revision protocol.

A pending photo does not prevent remote location refresh: the job/local photo
projection survives while authoritative location merges. Pending name edits also
overlay remote photo references. An uploaded reference never implicitly publishes
a complete animal. A photo selection cannot reclassify a pending legacy snapshot
and silently lose its unrelated fields.

The picker copies a file before save. A blocked location form leaves only an
unreferenced local file, no animal/outbox/upload job. Discovery scans persisted
animal records, not the photo directory, so that file cannot be published. Local
orphan-file garbage collection is deferred; no Storage cleanup was added.

## Legacy, terminality and account boundaries

Ambiguous full pending snapshots become `_animalConflict=LEGACY_LOCATION_AMBIGUOUS`,
with exact original payload retained in `_legacyAnimalPayload`. Pending is cleared
to avoid an automatic retry loop. No fields are converted into patches by guessing.
Unknown owner remains unknown; classification does not assert ownership. Conflict
state is queryable in SQLite for future resolution; there is no resolution UI yet.
Generic saves/refresh cannot erase it. Session cleanup and record removal protect
unresolved conflicts, patches and MOVE projections. Foreign-owner commands are not
processed. A terminal animal cannot be revived by local edit, stale refresh, upload
ACK or projection; remote PATCH also filters deleted_at IS NULL.

## Validation and scope

New tests: animal_patch_test.dart, animal_patch_remote_test.dart,
animal_patch_form_test.dart; original three animal_location_move_intent tests kept.
Photo tests now use explicit replacement/edit intent and cover narrow retry across
restart. Presence tests preserve positive existence/dependency assertions and
explicitly expect quarantine for old ambiguous MOVE snapshots.

Focused coverage includes real SQLite reopen/order/owner/conflict/overlay, mocked
HTTP field whitelists and predicates, CREATE ignore-duplicates, both photo/location
orders, widget touched-fields and blocked location save, abandoned local photo,
terminal precedence and stale GET after ACK. Existing photo cache/signed URL,
DELETE A/B/C, A1/A2, rotation, calendar and logout tests run in the complete suite.

Final D2 only: coordinated descriptive edit + MOVE, complete durable MOVE processing,
projection ACK/reconciliation and operator resolution of legacy conflicts. No
sync_move_animal invocation is implemented here. No remote SQL, migration change,
deploy, DELETE E work, commit or push.

## Final local validation (2026-10-02)

- flutter analyze: no issues.
- Complete suite: 420 passed, 5 known failures in expense_form_test / expense_list_test.
- Focused suites: 111/111 (19 store, 10 HTTP, 2 form, 3 boundary, 21 photo upload, 56 remote presence).
- Existing expense UI tests not edited.
- D1 SHA-256: `7f4ca6fdc45152c21c95564d586469df195872edc15347f242c8cc8cdc712232`.
- HEAD and local origin ref: `a20e8dd59b085b23fb91d54d83814fdb724174e3`.
- Branch: `feature/estructura-app-mvp`.
- git diff --check including untracked files: clean.

## Exact accumulated working-tree inventory

Includes preserved A1/A2 and partial A3 inputs, not only this continuation.

```text
 M lib/core/database/app_database.dart
 M lib/core/database/sync_metadata.dart
 M lib/features/animals/data/datasources/animal_local_datasource.dart
 M lib/features/animals/data/datasources/animal_remote_datasource.dart
 M lib/features/animals/data/repositories/animal_repository_impl.dart
 M lib/features/animals/data/services/animal_photo_sync.dart
 M lib/features/animals/domain/repositories/animal_repository.dart
 M lib/features/animals/presentation/screens/animal_screens.dart
 M lib/features/animals/presentation/viewmodels/animal_view_model.dart
 M lib/features/paddocks/data/datasources/paddock_local_datasource.dart
 M lib/features/paddocks/data/repositories/paddock_repository_impl.dart
 M lib/features/paddocks/domain/repositories/paddock_repository.dart
 M lib/features/paddocks/presentation/screens/paddock_screens.dart
 M lib/features/paddocks/presentation/viewmodels/paddock_view_model.dart
 M lib/features/sync/data/datasources/supabase_sync_remote_datasource.dart
 M lib/features/sync/data/datasources/sync_local_datasource.dart
 M lib/features/sync/data/datasources/sync_remote_datasource.dart
 M lib/features/sync/data/repositories/sync_repository_impl.dart
 M test/animal_photo_upload_test.dart
 M test/remote_presence_sync_test.dart
?? lib/core/database/animal_patch_store.dart
?? lib/core/database/paddock_patch_store.dart
?? lib/core/database/sync_failure.dart
?? lib/features/animals/domain/entities/animal_location_move_intent.dart
?? lib/features/animals/domain/value_objects/animal_patch.dart
?? lib/features/paddocks/domain/value_objects/paddock_patch.dart
?? supabase/DELETE_D2_A1.md
?? supabase/DELETE_D2_A2.md
?? supabase/DELETE_D2_A3_BOUNDARY.md
?? test/animal_location_move_intent_test.dart
?? test/animal_patch_form_test.dart
?? test/animal_patch_remote_test.dart
?? test/animal_patch_test.dart
?? test/deletion_state_test.dart
?? test/paddock_patch_form_test.dart
?? test/paddock_patch_remote_test.dart
?? test/paddock_patch_test.dart
```
