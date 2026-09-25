-- DELETE E1. Apply remotely ONLY after review and explicit authorization.
-- No Storage API, physical deletion, cron, or dependency on logical DELETE.
-- One-shot installation: existing E1 objects cause rollback, not replacement.
begin;
set local lock_timeout = '5s';
do $$
declare
  -- Narrow grammar for one comparison, not arbitrary SQL equivalence. Preserve
  -- the literal exactly; ignore only deparser whitespace/parentheses/text cast.
  v_deny_pattern constant text := '^[[:space:]()]*"?bucket_id"?[[:space:]()]*<>[[:space:]()]*''animal-photos''[[:space:]()]*(::text[[:space:]()]*)?$';
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'E1_REQUIRES_READ_COMMITTED';
  end if;
  if to_regclass('public.animal_photo_cleanup_jobs') is not null then
    raise exception 'E1_ALREADY_PRESENT';
  end if;
  if not exists(select 1 from storage.buckets where id='animal-photos' and name='animal-photos' and public=false) then
    raise exception 'E1_REQUIRES_PRIVATE_BUCKET';
  end if;
  if not exists(select 1 from pg_class where oid='storage.objects'::regclass and relrowsecurity)
     or not exists(select 1 from pg_class where oid='public.sync_deletions'::regclass and relrowsecurity) then
    raise exception 'E1_REQUIRES_RLS';
  end if;
  if not has_table_privilege('authenticated','public.sync_deletions','SELECT')
     or not has_table_privilege('service_role','public.sync_deletions','SELECT')
     or not exists(select 1 from pg_roles where rolname='service_role' and rolbypassrls) then
    raise exception 'E1_REQUIRES_REVIEWED_LEDGER_ACCESS';
  end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='animal_photos_insert_guard' and permissive='RESTRICTIVE'
      and cmd='INSERT' and roles=array['public']::name[]) then
    raise exception 'E1_INSERT_GUARD_BASELINE_MISMATCH';
  end if;
  -- Verify expressions too: reject OR/AND, different literals and other drift.
  -- PUBLIC is a singleton role list, so array ordering cannot differ here.
  if (select count(*) from pg_policies where schemaname='storage' and tablename='objects'
      and permissive='RESTRICTIVE' and roles=array['public']::name[]
      and qual ~ v_deny_pattern
      and ((policyname='animal_photos_no_delete' and cmd='DELETE')
        or (policyname='animal_photos_no_update' and cmd='UPDATE'
            and with_check ~ v_deny_pattern))) <> 2 then
    raise exception 'E1_STORAGE_GUARD_BASELINE_MISMATCH';
  end if;
end $$;

create function public.animal_photo_insert_allowed(p_name text)
returns boolean language plpgsql stable security invoker set search_path='' as $$
declare v_owner uuid; v_animal uuid; v_parts text[];
begin
  if auth.role() is distinct from 'authenticated' then return false; end if;
  v_owner := auth.uid();
  if v_owner is null or p_name is null then return false; end if;
  v_parts := pg_catalog.string_to_array(p_name,'/');
  if pg_catalog.cardinality(v_parts) is distinct from 3 then return false; end if;
  if v_parts[1] is distinct from v_owner::text then return false; end if;
  -- Canonical folders: uppercase UUID aliases would escape the lowercase prefix.
  if v_parts[2] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  if v_parts[3] !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.[a-zA-Z0-9]+$' then return false; end if;
  -- Procedural validation precedes cast; no dependence on SQL AND evaluation order.
  v_animal := v_parts[2]::uuid;
  return not exists(select 1 from public.sync_deletions d
    where d.collection='animals' and d.entity_id=v_animal and d.user_id=v_owner);
end $$;
revoke all on function public.animal_photo_insert_allowed(text) from public,anon,authenticated,service_role;
grant execute on function public.animal_photo_insert_allowed(text) to anon,authenticated;

create table public.animal_photo_cleanup_jobs (
  animal_id uuid primary key,
  user_id uuid not null,
  tombstone_sequence bigint not null unique references public.sync_deletions(sequence) on update restrict on delete restrict,
  tombstone_operation_id uuid not null,
  tombstone_deleted_at timestamptz not null,
  status text not null default 'pending' check(status in ('pending','leased','observed_empty','quarantined')),
  attempt_count bigint not null default 0 check(attempt_count>=0),
  -- Counts consecutive uncertain failures only; reset by a successful observation
  -- or a clearly transient result. Claims/crashes do not reset this counter.
  uncertain_failure_count integer not null default 0 check(uncertain_failure_count between 0 and 3),
  next_attempt_at timestamptz default clock_timestamp(),
  lease_token uuid,
  lease_expires_at timestamptz,
  generation bigint not null default 0 check(generation>=0),
  last_attempt_at timestamptz,
  last_error_code text check(last_error_code is null or last_error_code in (
    'storage_unavailable','rate_limited','timeout','permission_denied',
    'terminal_mismatch','invalid_namespace','legacy_conflict','no_progress','internal_error')),
  verified_empty_at timestamptz,
  next_verification_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint animal_photo_cleanup_schedule check (
    (status='pending' and next_attempt_at is not null and next_verification_at is null) or
    (status='observed_empty' and next_attempt_at is null and verified_empty_at is not null
      and next_verification_at is not null and next_verification_at>verified_empty_at) or
    (status in ('leased','quarantined') and next_attempt_at is null and next_verification_at is null)),
  constraint animal_photo_cleanup_lease check (
    (status='leased' and lease_token is not null and lease_expires_at is not null
      and last_attempt_at is not null and lease_expires_at>last_attempt_at and generation>0 and attempt_count>0) or
    (status<>'leased' and lease_token is null and lease_expires_at is null))
);
comment on table public.animal_photo_cleanup_jobs is 'Secondary reconstructible cleanup state; sync_deletions remains terminal authority.';
comment on column public.animal_photo_cleanup_jobs.verified_empty_at is 'Last observation, never a permanent guarantee. Reconciliation remains mandatory.';
create index animal_photo_cleanup_pending_due on public.animal_photo_cleanup_jobs(next_attempt_at,animal_id) where status='pending';
create index animal_photo_cleanup_expired_lease on public.animal_photo_cleanup_jobs(lease_expires_at,animal_id) where status='leased';
create index animal_photo_cleanup_verification_due on public.animal_photo_cleanup_jobs(next_verification_at,animal_id) where status='observed_empty';

create function public.animal_photo_cleanup_job_guard()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if tg_op='UPDATE' then
    if row(new.animal_id,new.user_id,new.tombstone_sequence,new.tombstone_operation_id,new.tombstone_deleted_at)
       is distinct from row(old.animal_id,old.user_id,old.tombstone_sequence,old.tombstone_operation_id,old.tombstone_deleted_at) then
      raise exception using errcode='23514',message='PHOTO_CLEANUP_IDENTITY_IMMUTABLE';
    end if;
    if new.generation<old.generation or new.attempt_count<old.attempt_count then
      raise exception using errcode='23514',message='PHOTO_CLEANUP_COUNTER_REGRESSION';
    end if;
    new.created_at := old.created_at;
  else new.created_at := v_now;
  end if;
  if not exists(select 1 from public.sync_deletions d where d.sequence=new.tombstone_sequence
      and d.collection='animals' and d.entity_id=new.animal_id and d.user_id=new.user_id
      and d.operation_id=new.tombstone_operation_id and d.deleted_at=new.tombstone_deleted_at) then
    raise exception using errcode='23514',message='PHOTO_CLEANUP_TERMINAL_MISMATCH';
  end if;
  new.updated_at := v_now;
  return new;
end $$;
revoke all on function public.animal_photo_cleanup_job_guard() from public,anon,authenticated,service_role;
create trigger animal_photo_cleanup_job_guard before insert or update on public.animal_photo_cleanup_jobs
for each row execute function public.animal_photo_cleanup_job_guard();
alter table public.animal_photo_cleanup_jobs enable row level security;
revoke all on public.animal_photo_cleanup_jobs from public,anon,authenticated,service_role;
grant select,insert,update on public.animal_photo_cleanup_jobs to service_role;
create policy animal_photo_cleanup_no_clients on public.animal_photo_cleanup_jobs
as restrictive for all to anon,authenticated using(false) with check(false);

create function public.discover_animal_photo_cleanup_jobs(p_limit integer default 1000)
returns integer language plpgsql security invoker set search_path='' as $$
declare v_count integer;
begin
  if p_limit is null or p_limit<1 or p_limit>5000 then
    raise exception using errcode='22023',message='PHOTO_CLEANUP_INVALID_BATCH_SIZE';
  end if;
  insert into public.animal_photo_cleanup_jobs(animal_id,user_id,tombstone_sequence,tombstone_operation_id,tombstone_deleted_at)
  select d.entity_id,d.user_id,d.sequence,d.operation_id,d.deleted_at
  from public.sync_deletions d where d.collection='animals'
    and not exists(select 1 from public.animal_photo_cleanup_jobs j where j.animal_id=d.entity_id)
  order by d.sequence limit p_limit on conflict(animal_id) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end $$;

create function public.claim_animal_photo_cleanup_job()
returns setof public.animal_photo_cleanup_jobs language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_now timestamptz;
begin
  if pg_catalog.current_setting('transaction_isolation')<>'read committed' then
    raise exception using errcode='0A000',message='PHOTO_CLEANUP_REQUIRES_READ_COMMITTED';
  end if;
  v_now := pg_catalog.clock_timestamp();
  select j.animal_id into v_id from public.animal_photo_cleanup_jobs j
  where (j.status='pending' and j.next_attempt_at<=v_now)
     or (j.status='leased' and j.lease_expires_at<=v_now)
     or (j.status='observed_empty' and j.next_verification_at<=v_now)
  order by coalesce(j.next_attempt_at,j.lease_expires_at,j.next_verification_at),j.animal_id
  limit 1 for update skip locked;
  if not found then return; end if;
  v_now := pg_catalog.clock_timestamp();
  return query update public.animal_photo_cleanup_jobs j set status='leased',
    attempt_count=j.attempt_count+1,generation=j.generation+1,
    lease_token=pg_catalog.gen_random_uuid(),lease_expires_at=v_now+interval '120 seconds',
    last_attempt_at=v_now,next_attempt_at=null,next_verification_at=null
  where j.animal_id=v_id returning j.*;
end $$;

-- Trusted E2 worker reports a verified result. This function never accesses Storage.
-- Invoker server privileges are not a boundary against a malicious administrator.
create function public.finish_animal_photo_cleanup_attempt(
  p_animal_id uuid,p_lease_token uuid,p_generation bigint,p_outcome text,p_error_code text default null)
returns boolean language plpgsql security invoker set search_path='' as $$
declare
  v_job public.animal_photo_cleanup_jobs%rowtype;
  v_now timestamptz; v_delay interval; v_uncertain integer; v_status text;
begin
  if pg_catalog.current_setting('transaction_isolation')<>'read committed' then
    raise exception using errcode='0A000',message='PHOTO_CLEANUP_REQUIRES_READ_COMMITTED';
  end if;
  if p_outcome is null or p_outcome not in ('retry','observed_empty','quarantined') then
    raise exception using errcode='22023',message='PHOTO_CLEANUP_INVALID_OUTCOME';
  end if;
  if (p_outcome='observed_empty' and p_error_code is not null)
     or (p_outcome='retry' and (p_error_code is null or p_error_code not in (
       'storage_unavailable','rate_limited','timeout','internal_error','permission_denied','no_progress')))
     or (p_outcome='quarantined' and (p_error_code is null or p_error_code not in (
       'terminal_mismatch','invalid_namespace','legacy_conflict'))) then
    raise exception using errcode='22023',message='PHOTO_CLEANUP_INVALID_ERROR_CLASS';
  end if;
  select j.* into v_job from public.animal_photo_cleanup_jobs j where j.animal_id=p_animal_id for update;
  if not found then return false; end if;
  v_now := pg_catalog.clock_timestamp(); -- AFTER lock, never acknowledge an expired lease.
  if v_job.status<>'leased' or v_job.lease_token is distinct from p_lease_token
     or v_job.generation is distinct from p_generation or v_job.lease_expires_at<=v_now then return false; end if;
  v_uncertain := v_job.uncertain_failure_count;
  if p_outcome='retry' then
    if p_error_code in ('internal_error','permission_denied','no_progress') then
      v_uncertain := least(v_uncertain+1,3);
    else v_uncertain := 0;
    end if;
    v_status := case when v_uncertain=3 then 'quarantined' else 'pending' end;
    v_delay := case when v_job.attempt_count=1 then interval '5 seconds'
      when v_job.attempt_count=2 then interval '15 seconds'
      when v_job.attempt_count=3 then interval '30 seconds'
      when v_job.attempt_count=4 then interval '1 minute' else interval '5 minutes' end;
    update public.animal_photo_cleanup_jobs set status=v_status,
      uncertain_failure_count=v_uncertain,
      next_attempt_at=case when v_status='pending' then v_now+v_delay else null end,
      next_verification_at=null,lease_token=null,lease_expires_at=null,last_error_code=p_error_code
    where animal_id=p_animal_id;
  elsif p_outcome='observed_empty' then
    v_delay := case when v_job.verified_empty_at is null then interval '1 minute'
      when v_now<v_job.tombstone_deleted_at+interval '1 hour' then interval '10 minutes'
      when v_now<v_job.tombstone_deleted_at+interval '1 day' then interval '1 hour'
      when v_now<v_job.tombstone_deleted_at+interval '7 days' then interval '1 day' else interval '7 days' end;
    update public.animal_photo_cleanup_jobs set status='observed_empty',uncertain_failure_count=0,
      next_attempt_at=null,verified_empty_at=v_now,next_verification_at=v_now+v_delay,
      lease_token=null,lease_expires_at=null,last_error_code=null where animal_id=p_animal_id;
  else
    update public.animal_photo_cleanup_jobs set status='quarantined',next_attempt_at=null,
      next_verification_at=null,lease_token=null,lease_expires_at=null,last_error_code=p_error_code
    where animal_id=p_animal_id;
  end if;
  return true;
end $$;
revoke all on function public.discover_animal_photo_cleanup_jobs(integer) from public,anon,authenticated,service_role;
revoke all on function public.claim_animal_photo_cleanup_job() from public,anon,authenticated,service_role;
revoke all on function public.finish_animal_photo_cleanup_attempt(uuid,uuid,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.discover_animal_photo_cleanup_jobs(integer) to service_role;
grant execute on function public.claim_animal_photo_cleanup_job() to service_role;
grant execute on function public.finish_animal_photo_cleanup_attempt(uuid,uuid,bigint,text,text) to service_role;
do $$ declare v_count integer; begin
  loop v_count := public.discover_animal_photo_cleanup_jobs(1000); exit when v_count=0; end loop;
end $$;
alter policy animal_photos_insert_guard on storage.objects
with check(bucket_id<>'animal-photos' or public.animal_photo_insert_allowed(name));
-- SELECT, no_update, no_delete, native Storage triggers and all domain contracts stay unchanged.
commit;
