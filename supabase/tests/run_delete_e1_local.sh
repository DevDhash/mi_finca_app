#!/usr/bin/env bash
# Local Docker only: no ports, no network, no Supabase credentials/CLI.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
container="mi-finca-e1c-${RANDOM}-$$"
logs="$(mktemp -d "${TMPDIR:-/tmp}/delete-e1c.XXXXXX")"
cleanup() { docker stop "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Uses an existing/downloaded public PostgreSQL image, never a linked Supabase project.
docker run --rm -d --name "$container" --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=mi_finca_delete_e1_test \
  --mount "type=bind,source=$repo_root/supabase,target=/work,readonly" \
  postgres:17-alpine > "$logs/container.txt"
psql_local() { docker exec "$container" psql -X -U postgres -d mi_finca_delete_e1_test -v ON_ERROR_STOP=1 "$@"; }
for ((i=0;i<100;i++)); do
  if docker exec "$container" sh -c 'test "$(cat /proc/1/comm)" = postgres' >/dev/null 2>&1 && psql_local -Atc 'select 1' >/dev/null 2>&1; then break; fi
  sleep 0.1
done
# Extract the actual migration preflight, never a hand-written replica.
preflight="$(sed -n '/^do \$\$$/,/^end \$\$;/p' "$repo_root/supabase/migrations/20260924000300_animal_photo_cleanup_contract.sql")"
psql_local -v preflight="$preflight" -v rollback_roundtrip=1 -f /work/tests/delete_e1_local.sql > "$logs/main.log" 2>&1 || { cat "$logs/main.log"; exit 1; }
# Exactly one eligible fixture for deterministic claim contention.
psql_local -c "update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()+interval '1 day' where status='pending'; update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=public.test_id(10);" > "$logs/prepare.log"
psql_local -f /work/tests/delete_e1_concurrency_a.sql > "$logs/claim-a.log" 2>&1 &
claim_pid=$!
barrier=false
for ((i=0;i<100;i++)); do
  if [[ "$(psql_local -Atc "select count(*) from pg_stat_activity where application_name='e1_claim_a' and wait_event='PgSleep'")" == 1 ]]; then barrier=true; break; fi
  sleep 0.05
done
if [[ "$barrier" != true ]]; then echo 'Claim barrier not reached'; cat "$logs/claim-a.log"; exit 1; fi
psql_local -f /work/tests/delete_e1_concurrency_b.sql > "$logs/claim-b.log" 2>&1
wait "$claim_pid"
# Concurrent discovery: A inserts an absent job and holds its transaction;
# B must wait on uniqueness and then return zero without altering that job.
psql_local -c "delete from public.animal_photo_cleanup_jobs where animal_id=public.test_id(11);" >/dev/null
psql_local -c "begin; set local role service_role; set local application_name='e1_discover_a'; select public.test_ok(40,'first concurrent discovery inserts one',public.discover_animal_photo_cleanup_jobs()=1); select pg_sleep(8); commit;" > "$logs/discover-a.log" 2>&1 &
discover_pid=$!
barrier=false
for ((i=0;i<100;i++)); do
  if [[ "$(psql_local -Atc "select count(*) from pg_stat_activity where application_name='e1_discover_a' and wait_event='PgSleep'")" == 1 ]]; then barrier=true; break; fi
  sleep 0.05
done
if [[ "$barrier" != true ]]; then echo 'Discovery barrier not reached'; exit 1; fi
psql_local -c "set role service_role; select public.test_ok(41,'second concurrent discovery no duplicate',public.discover_animal_photo_cleanup_jobs()=0);" > "$logs/discover-b.log" 2>&1
wait "$discover_pid"
psql_local -c "select n,label from public.test_results order by n; select public.test_ok(42,'all mandatory tests present',not exists(select 1 from generate_series(1,34) as required(n) where not exists(select 1 from public.test_results t where t.n=required.n)));"
# Neither one-shot rerun nor rollback after operational activity may destroy jobs.
before_state="$(psql_local -Atc "select md5(jsonb_agg(to_jsonb(j) order by animal_id)::text) from public.animal_photo_cleanup_jobs j")"
if psql_local -f /work/tests/delete_e1_rollback_local.sql > "$logs/blocked-rollback.log" 2>&1; then
  echo 'Unsafe rollback unexpectedly succeeded'; exit 1
fi
if ! grep -q 'E1_ROLLBACK_REQUIRES_PRESERVING_OPERATIONAL_JOBS' "$logs/blocked-rollback.log"; then
  cat "$logs/blocked-rollback.log"; exit 1
fi
if psql_local -f /work/migrations/20260924000300_animal_photo_cleanup_contract.sql > "$logs/reapply.log" 2>&1; then
  echo 'One-shot reinstall unexpectedly succeeded'; exit 1
fi
if ! grep -q 'E1_ALREADY_PRESENT' "$logs/reapply.log"; then cat "$logs/reapply.log"; exit 1; fi
after_state="$(psql_local -Atc "select md5(jsonb_agg(to_jsonb(j) order by animal_id)::text) from public.animal_photo_cleanup_jobs j")"
[[ "$before_state" == "$after_state" ]] || { echo 'Failed rollback/reinstall modified jobs'; exit 1; }
psql_local -c "select public.test_ok(43,'operational rollback and reinstall rejected without mutation',true);"
psql_local -f /work/tests/delete_e1_extra.sql > "$logs/extra.log" 2>&1 || { cat "$logs/extra.log"; exit 1; }
psql_local -c "select n,label from public.test_results order by n; select count(*) as passed from public.test_results;"
printf 'Logs: %s\n' "$logs"
