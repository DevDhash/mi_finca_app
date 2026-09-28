# DELETE D1 — installed and validated in production

## Installed artifact (operator-confirmed, 2026-09-28)

Project: fgzaddfcbiriocpbwreb. The operator manually applied
`20260928000100_delete_d1_paddock_movement_contract.sql` successfully
("Success. No rows returned"). Corrected Hosted preflight PASS; production
postflight PASS. These remote facts were reported by the operator; finalization
performs no additional remote SQL or remote inspection.

Installed SHA-256:
`7f4ca6fdc45152c21c95564d586469df195872edc15347f242c8cc8cdc712232`.
This installed migration is now immutable. Do not edit or rerun it.

Postflight confirmed postgres ownership and RLS on sync_movement_operations,
7 new SECURITY DEFINER functions and 6 D1 triggers. Receipt SELECT/INSERT/UPDATE/
DELETE are false for anon, authenticated and service_role. anon cannot execute
either RPC; authenticated and service_role can execute both (RPC owner checks
still apply). Initial receipt_count=0, expected: Flutter has NOT yet adopted
sync_move_animal. Existing DELETE A tombstones remain animals=4, expenses=1.
Lima boundary checks: 2026-09-13T04:59:59Z -> September 12;
2026-09-13T05:00:00Z -> September 13.

DELETE E: cleanup funcional validado; automatic wakeup pendiente.
Automation remains suspended and unrelated to D1. The preserved
`20260926000100_cleanup_automation_security_hardening.sql` remains NOT APPLIED.
Do not apply it, run generic migration deployment, or execute rollback as part
of finalization. A manual SQL Editor application does not by itself establish
that the CLI migration-history table was updated; reconcile deployment history
only through a separately reviewed procedure before any future deployment.

## Authoritative business calendar (intentional normalization)

America/Lima CALENDAR DAYS, not device-local midnight or elapsed 24-hour blocks.
PostgreSQL: `(T AT TIME ZONE 'America/Lima')::date`; subtract dates.
Dart: convert the instant with bundled IANA timezone data, extract year/month/day,
then construct a UTC date carrier. Difference of those carriers counts civil
days, never local DST hours. No setLocalLocation, device settings or server
session TimeZone dependency. Uses timezone 0.10.1 (BSD-2-Clause); pure Dart,
embedded database, no runtime network/service/payment. Bundled timezone rules
must be kept compatible with server tzdata if Peru changes legislation.

The old device-local Duration behavior is intentionally superseded. Inputs are
instants: different offsets representing the same instant give the same answer.
A naive legacy string without offset does not identify a portable instant. D1
normalizes calculation, not old serialized data or date-picker UX; future RPC
integration must send moved_at with explicit UTC/offset. No historical timestamp
backfill is performed here.

Valid plan: required_rest_days > 0, end exists, end Lima date <= reference Lima
date. Completed: reference date minus end date >= required_rest_days.

| Status | canReceiveAnimals |
| --- | --- |
| Agotado | false |
| En uso | true |
| Descansando | valid plan AND completed |
| Disponible / other (including database NULL mapped to Disponible in Flutter) | NOT(valid plan AND incomplete) |

NULL/nonpositive rest days, NULL end or future end invalidate the plan. No
rotation_order, pasture_type, grazing_start_date, planned_grazing_days or farm_id
participates. RPC raises SYNC_PADDOCK_NOT_AVAILABLE before mutations when false.
Ownership and terminal guards run first. Shared JSON fixtures exercise client
and SQL with identical timestamps, statuses and expected results.

## Durable receipt / API

`sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer DEFAULT NULL)`:
owner, animal, movement ID, expected source, destination, instant, planned days.
Returns original movement JSON. New `public.sync_movement_operations`, owned by
postgres (installer guard), has movement_id PK, user_id, animal_id, nullable
from_paddock_id, to_paddock_id, moved_at, plan_applied, planned_grazing_days,
result JSONB and completed_at. No FK cascade or farm dependency. RLS enabled,
no client policies; all table privileges revoked from PUBLIC/anon/authenticated/
service_role. Only the narrow definer RPC inserts; trusted DB owner can administer.
Clients do not need SELECT. No receipt retention/deletion task for MVP.

Receipt is inserted after animal+history+paddock effects, in the same transaction.
Any failure, including after receipt insertion, rolls ALL of them back. Receipt
existence proves this RPC committed, unlike an arbitrary movement row.

Retry: owner checked first; compare animal/source/destination/moved_at and
normalized meaningful plan. Return immutable stored result, never replay,
including after later moves or terminal changes. Foreign owner -> generic
SYNC_NOT_AUTHORIZED, no receipt details. Changed payload -> SYNC_MOVE_ID_CONFLICT.
Existing movement without receipt -> SYNC_MOVE_LEGACY_CONFLICT, no repair or
mutation. Missing physical movement with terminal ledger and no receipt remains
SYNC_ENTITY_DELETED. Source mismatch on a fresh move -> SYNC_MOVE_SOURCE_CONFLICT.

Plan normalization: empty destination requires positive days and receipt records
plan_applied=true plus supplied days. Retry NULL/different positive days conflicts.
Occupied destination preserves its existing plan; receipt records false/NULL and
ignores the unused positive/NULL request plan on retry. Invalid fresh input days
<=0 is SYNC_INVALID_MOVE. All receipts are immutable to ordinary clients.

## Supported lock protocol, NOT universal deadlock freedom

Global G = hashtextextended('delete-d1:movement-domain',0), transaction advisory.
Ordinary INSERT/UPDATE statements enter G through BEFORE STATEMENT triggers;
RPCs enter G before their controlled row operations. No per-owner partitioning:
unrelated users serialize, deliberate MVP cost. Keep transactions short.

DELETE A entity keys E(collection,id) remain unchanged. DELETE RPC: G -> E ->
row FOR UPDATE. Direct UPDATE: G -> row -> E in existing terminal trigger.
MOVE: G -> animal FOR UPDATE -> source/destination FOR UPDATE sorted UUID ->
updates/insertion triggering E for animal/movement/paddocks. Reacquiring G/E in
same transaction is safe. Inner E/row order is not globally identical; G excludes
competing supported writers before that inversion matters. Changing DELETE A
identity lock order would increase scope/risk and is not done.

External/custom transactions that pre-lock rows before entering D1 can deadlock.
No guarantee for disabled triggers, replication-role bypass or administrative
hard-delete flows. PostgreSQL deadlock/timeout failures must retry the whole
transaction. SQL test statements have 15s statement_timeout; contender must be
observed waiting on advisory lock before winner commits; no pg_sleep.

MOVE-first commits occupancy then DELETE rejects. DELETE-first commits terminal
then MOVE rejects. Source departure-first allows deletion of emptied source.
Occupied source delete rejects without ledger. Direct history insertion does
not itself create occupancy and cannot prevent later deletion of an empty
paddock. Concurrent RPC duplicate returns one receipt/history.

## Effects and old clients

Occupancy: own animal with deleted_at IS NULL and matching paddock_id, no status
or farm test. Generic DELETE A remains authority; first ledger only after empty
check. Direct soft-delete has same occupancy guard. Existing timestamp and
terminal triggers retained. No historical updates, hard delete or FK/RLS changes
to domain tables.

MOVE changes animal.paddock_id; inserts supplied movement; occupied source stays
En uso; empty source becomes Descansando, clears start/plan, sets end to real
movement instant. Destination becomes En uso, clears last end, sets start/plan
only when previously empty. Existing updated_at triggers run. Never renumbers
rotation, changes rest days/pasture/farm or activates unrelated paddocks.

Old clients: separate requests remain potentially partial. New RPC: atomic plus
receipt. Both reject NEW terminal/foreign references. Historical unchanged
references remain valid. Historical UPSERT may fail in BEFORE INSERT against a
terminal destination; do not weaken protection. Existing generic Flutter sync
still catches errors as pending; future integration must classify business
conflicts and route atomic operations, not ACK SYNC_MOVE_LEGACY_CONFLICT or retry
it forever as network failure. This phase does not adopt the RPC in Flutter.

## Objects / privileges / preflight

Replaces sync_soft_delete(text,uuid,uuid,uuid), adds sync_move_animal and
six helpers: d1_lock_domain(), d1_lock_statement(), d1_assert_empty(uuid,uuid),
d1_assert_paddock(uuid,uuid,boolean), d1_guard_references(),
d1_can_receive_animals(text,integer,timestamptz,timestamptz).
All SECURITY DEFINER, search_path ''. New receipt table as above. Six triggers:
d1_domain_gate BEFORE INSERT OR UPDATE STATEMENT and d1_reference_guard BEFORE
INSERT OR UPDATE ROW, each on paddocks/animals/animal_movements. RPC EXECUTE to
authenticated only among client roles; helpers revoked from client roles.

Installation preflights names, ownership, required column types, unhandled
mandatory movement columns and existing assignment conflicts. Receipt/functions
name collisions fail before CREATE. Additional SELECT-only catalog checks are
in tests/delete_d1/corrected_hosted_preflight.sql; execute only after review.
Production provided baseline: 9 paddocks, 15 animals, all farm_id NULL, two occupied
paddocks, no terminal/reference inconsistencies. No domain data is changed by
installation. Fixture tests are not certification of unseen Hosted DDL.

## Rollback

rollback/delete_d1.sql rejects if ANY completed receipt exists. Do not drop
proofs of successful operations. With no receipts and clients stopped, it drops
D1 table/helpers/triggers and restores the DELETE A RPC; no domain/history/ledger
rows deleted. If operations have occurred, prefer forward fix or separately
review a receipt-preserving rollback. Never manually empty receipts to bypass
this guard. PostgreSQL RLS has no receipt policies to remove; table drop removes
its constraints/security metadata only when empty.

## Local validation

PostgreSQL disposable fixture without network/ports/credentials: original DELETE A
suite plus corrected D1, actual session races, injected failure rollback, ACL and
shared calendar scenarios. Static tests supplement actual PostgreSQL tests.
Flutter suites include business calendar, rotation, movements, DELETE A/C and sync.
No unrelated expense UI tests corrected. All SQL test execution is confined to
disposable local PostgreSQL. Finalization authorizes a separate D1 commit/push
after validation; it does not authorize any further remote SQL.

Latest results: 40 PostgreSQL scenario groups PASS; 5 static tests PASS;
179 Flutter tests PASS; additional calendar-only process with TZ=America/New_York
20/20 PASS; flutter analyze PASS; targeted dart format PASS; git diff --check
and new-file whitespace review PASS. Test fixtures contain no production IDs.
