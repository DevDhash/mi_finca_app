# DELETE D2 — local MOVE adoption and final audit

No remote SQL, D1 edit, deploy, DELETE E change, commit or push.

## Active flow

Animal UI -> moveMany / MoveAnimal -> AnimalMoveRepository.saveAtomicMovement
-> owner read from SQLite session -> saveAtomicMove -> createAnimalMove transaction.
The transaction creates exactly one durable animal_move_commands entry, one animal
_moveProjection and one non-pending localOnly provisional history row. movementId
is shared by all three. plannedGrazingDays is forwarded unchanged for every animal
in a batch; D1 owns normalization when later calls find an occupied destination.
The batch has no separate paddock saves or invented interval dates/rotation.

Generic sync skips MOVE commands. The dedicated processor sends sync_move_animal,
validates its receipt, reads current animal/paddock state and reconciles locally.
Only that RPC writes remotely for the new MOVE. Reads use owner predicates and
maybeSingle; missing rows are neither ACKs nor tombstones. Historical paddocks
that are absent or already deleted do not prevent confirming accepted history.
Current remote location can differ from the old receipt destination because a
later device may already have moved the animal again.

## Evidence, crash recovery and concurrent edits

Reconciliation stores the exact validated receipt on the local movement and
confirms its remote presence. It preserves current animal/photo fields, pending
bits and descriptive patches. Paddock operational fields come from remote state;
A2 overlays preserve independent descriptive patches. Terminal local entities
are never replaced by an active snapshot.

Completion requires the positive durable movement evidence. If the app closes
between reconciliation and command completion, a retry of the same movementId
uses the receipt plus confirmed local movement identity to reconcile again even
without _moveProjection. A projection for another command is never removed.
Another local MOVE cannot start in this crash window. Pending full paddock writes
or operational patches must be resolved before creating MOVE; descriptive patches
remain independent. Generic CAS/markAllSynced/markRecordSynced/removeRecord cannot
acknowledge or discard the MOVE command or its linked provisional history.

## Rejection

Only exact installed business codes with the expected SQLSTATE become conflicts.
Unknown errors stay pending; auth failures are not business conflicts. A terminal
error alone is not evidence: sync pulls the ledger before a terminal transition.

A business rejection atomically records conflict, flags the matching projection
as rejected and hides only its localOnly provisional history. It does not erase
accepted history. An owner-validated active animal read supplies current location
and clears only the matching projection; it never blindly restores the expected
source. Without evidence the projection stays explicitly unconfirmed and the
animal list labels the conflict. Conflict recovery reads do not reinvoke the RPC.
Manual synchronization processes recovery even when pendingCount is zero.

Conflicts remain durable audit records. There is no new UI to discard/resolve a
MOVE conflict and authorize another command after review. Conservative unresolved
MOVE guards continue to block logout/clear/new MOVE until an explicit resolution
workflow is provided. Do not describe this as a complete conflict-resolution UX.

## Paddock DELETE

The detail action creates the existing A1 durable deletion intent. SQLite checks
active occupancy and outstanding source/destination MOVE dependencies atomically.
No animal location or historical movement is changed. Remote occupied rejection
is read back through an owner-filtered active row and the existing A1 reconciliation
primitive; missing rows cannot restore the paddock or confirm deletion. Terminal
ledger evidence wins. A missing/deleted detail row renders unavailable rather
than throwing firstWhere. No rotation renumbering or automatic activation occurs.

## Legacy

Current UI does not call saveMove/saveMovement/upsertMovement. Direct remote
upsertMovement now rejects use. Local saveMove/saveMovement are retained for old
fixtures/compatibility and hydration; repository history hydration continues to
call saveMovement with pending=false and verified owner. Existing legacy outbox
movement rows retain the C1 dependency protocol. Ambiguous legacy animal snapshots
remain A3 conflicts and are never converted into a new MOVE by guessing.

## Remaining physical validation / limitations

- D4 must exercise two devices, airplane mode/restart, lost response and races
  with DELETE on the already installed D1; no remote tests were performed here.
- A new animal/paddock must have confirmed remote presence before MOVE.
- Combined descriptive edit + location change in AnimalForm remains blocked;
  the dedicated movement UI is the adopted path.
- Explicit UI resolution of durable conflicts is still absent (see above).
- Reads after RPC are current state from separate SELECTs, not a snapshot of the
  original MOVE transaction; subsequent sync/refresh handles later server changes.

## Local validation

- flutter analyze: no issues.
- Focused broad D2 suites: 196 passed before final extra regressions.
- Final focused suites: 94/94 passed.
- Final full suite (concurrency=2): 445 passed, 5 historical expense UI failures
  (2 expense_form_test.dart, 3 expense_list_test.dart). No expense tests changed.
- Earlier parallel run hit two suite-load timeouts; final bounded-concurrency run
  completed without those timeouts.
- git diff --check, including new files: clean.
- D1 SHA-256 unchanged: 7f4ca6fdc45152c21c95564d586469df195872edc15347f242c8cc8cdc712232.

## Exact accumulated file inventory

Includes preserved A1/A2/A3 and FINAL work; not all entries originated in this pass.

```text
 M lib/core/database/app_database.dart
 M lib/core/database/sync_metadata.dart
 M lib/features/animals/data/datasources/animal_local_datasource.dart
 M lib/features/animals/data/datasources/animal_remote_datasource.dart
 M lib/features/animals/data/models/animal_model.dart
 M lib/features/animals/data/repositories/animal_repository_impl.dart
 M lib/features/animals/data/services/animal_photo_sync.dart
 M lib/features/animals/domain/entities/animal.dart
 M lib/features/animals/domain/repositories/animal_repository.dart
 M lib/features/animals/domain/usecases/move_animal.dart
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
 M lib/features/sync/presentation/viewmodels/sync_view_model.dart
 M test/animal_deletion_test.dart
 M test/animal_photo_upload_test.dart
 M test/photo_sync_view_model_test.dart
 M test/remote_presence_sync_test.dart
?? lib/core/database/animal_move_store.dart
?? lib/core/database/animal_patch_store.dart
?? lib/core/database/paddock_patch_store.dart
?? lib/core/database/sync_failure.dart
?? lib/features/animals/domain/entities/animal_location_move_intent.dart
?? lib/features/animals/domain/value_objects/animal_move_command.dart
?? lib/features/animals/domain/value_objects/animal_patch.dart
?? lib/features/paddocks/domain/value_objects/paddock_patch.dart
?? supabase/DELETE_D2_A1.md
?? supabase/DELETE_D2_A2.md
?? supabase/DELETE_D2_A3_BOUNDARY.md
?? supabase/DELETE_D2_FINAL.md
?? test/animal_location_move_intent_test.dart
?? test/animal_move_sync_test.dart
?? test/animal_patch_form_test.dart
?? test/animal_patch_remote_test.dart
?? test/animal_patch_test.dart
?? test/deletion_state_test.dart
?? test/paddock_delete_ui_test.dart
?? test/paddock_patch_form_test.dart
?? test/paddock_patch_remote_test.dart
?? test/paddock_patch_test.dart
```
