-- DELETE A. REVIEW AND APPLY MANUALLY; this file is not deployed by Flutter.
-- Prerequisite: all five domain tables have UUID id/user_id and deleted_at timestamptz.
-- No physical domain deletion, FK changes, Storage changes or data removal.
begin;

-- Fail rather than wait indefinitely for production writers; the transaction rolls back.
set local lock_timeout = '10s';

-- Prevent a writer from slipping between the initial tombstone backfill and guards.
lock table public.farms, public.paddocks, public.animals,
  public.animal_movements, public.expenses in share row exclusive mode;

create table if not exists public.sync_deletions (
  sequence bigint generated always as identity unique,
  collection text not null check (collection in
    ('farms', 'paddocks', 'animals', 'movements', 'expenses')),
  entity_id uuid not null,
  -- Keep terminal identities independent of future account-deletion workflows.
  -- No new FK or CASCADE is introduced by DELETE A.
  user_id uuid not null,
  deleted_at timestamptz not null default clock_timestamp(),
  operation_id uuid not null,
  primary key (collection, entity_id)
);
-- Serializes installation/backfill against RPC writes, including absent identities.
lock table public.sync_deletions in share row exclusive mode;

create index if not exists sync_deletions_owner_sequence
  on public.sync_deletions (user_id, sequence);

alter table public.sync_deletions enable row level security;
revoke all on public.sync_deletions from public, anon, authenticated;
grant select on public.sync_deletions to authenticated;
-- Supabase default privileges can grant sequence access independently of tables.
-- Clients must not advance/reset this identity outside the definer functions.
do $$
declare identity_sequence text := pg_catalog.pg_get_serial_sequence('public.sync_deletions', 'sequence');
begin
  if identity_sequence is null then
    raise exception 'DELETE A requires the expected sync_deletions identity schema';
  end if;
  execute pg_catalog.format('revoke all on sequence %s from public, anon, authenticated', identity_sequence);
end;
$$;
-- Clients can read their terminal identities, never insert/update/purge the ledger.
drop policy if exists sync_deletions_read_own on public.sync_deletions;
create policy sync_deletions_read_own on public.sync_deletions
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists sync_deletions_read_guard on public.sync_deletions;
create policy sync_deletions_read_guard on public.sync_deletions
  as restrictive for select to public
  using (auth.uid() is not null and user_id = (select auth.uid()));

-- Trigger owner must be the trusted migration role. Fixed search_path and fully
-- qualified objects prevent name hijacking. Not callable as an application RPC.
create or replace function public.sync_guard_entity()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  entity_collection text := case when tg_table_name = 'animal_movements'
    then 'movements' else tg_table_name end;
  terminal public.sync_deletions%rowtype;
begin
  -- Advisory locks require fresh snapshots after waiting. Reject older fixed
  -- snapshots rather than allowing a terminal identity to be missed.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '0A000', message = 'SYNC_REQUIRES_READ_COMMITTED';
  end if;

  if tg_table_schema <> 'public' or tg_table_name not in
     ('farms', 'paddocks', 'animals', 'animal_movements', 'expenses') or
     tg_op not in ('INSERT', 'UPDATE') then
    raise exception using errcode = '42501', message = 'SYNC_INVALID_TARGET';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(entity_collection || ':' || new.id::text, 0));

  if tg_op = 'UPDATE' then
    -- Deleted -> ANY update is terminal, including a no-op or payload-only edit.
    if old.deleted_at is not null then
      raise exception using errcode = 'P0001', message = 'SYNC_ENTITY_DELETED';
    end if;
    if new.id is distinct from old.id or new.user_id is distinct from old.user_id then
      raise exception using errcode = '42501', message = 'SYNC_IDENTITY_IMMUTABLE';
    end if;
  end if;

  select * into terminal from public.sync_deletions
    where collection = entity_collection and entity_id = new.id;

  if tg_op = 'INSERT' then
    -- Also runs BEFORE the conflict branch of an old client's direct UPSERT.
    -- Same generic error for own/foreign terminal identities; never reveal owner.
    if terminal.entity_id is not null or new.deleted_at is not null then
      raise exception using errcode = 'P0001', message = 'SYNC_ENTITY_DELETED';
    end if;
    return new;
  end if;

  -- Active -> deleted is the ONLY deletion transition.
  if old.deleted_at is null and new.deleted_at is not null then
    if terminal.entity_id is not null and terminal.user_id is distinct from new.user_id then
      raise exception using errcode = 'P0001', message = 'SYNC_ENTITY_DELETED';
    end if;
    -- updated_at is reserved for existing timestamp triggers, not business data.
    if (pg_catalog.to_jsonb(new) - 'deleted_at' - 'updated_at') is distinct from
       (pg_catalog.to_jsonb(old) - 'deleted_at' - 'updated_at') then
      raise exception using errcode = 'P0001', message = 'SYNC_DELETE_ONLY';
    end if;
    if terminal.entity_id is null then
      -- Direct legacy soft delete: generate its own operation once.
      insert into public.sync_deletions(collection, entity_id, user_id, operation_id)
        values (entity_collection, new.id, new.user_id, pg_catalog.gen_random_uuid())
        returning * into terminal;
    end if;
    -- RPC already inserted its ledger: preserve p_operation_id, sequence and time.
    new.deleted_at := terminal.deleted_at;
    return new;
  end if;

  -- Active -> active is allowed only while this identity is not terminal.
  if terminal.entity_id is not null then
    raise exception using errcode = 'P0001', message = 'SYNC_ENTITY_DELETED';
  end if;
  return new;
end;
$$;
revoke all on function public.sync_guard_entity() from public, anon, authenticated;

create or replace function public.sync_soft_delete(
  p_collection text, p_entity_id uuid, p_owner_id uuid, p_operation_id uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  target_table text;
  actual_owner uuid;
  previous_deleted_at timestamptz;
  terminal public.sync_deletions%rowtype;
begin
  -- Advisory locks require fresh snapshots after waiting. Reject older fixed
  -- snapshots rather than allowing a terminal identity to be missed.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '0A000', message = 'SYNC_REQUIRES_READ_COMMITTED';
  end if;

  if auth.uid() is null or p_owner_id is distinct from auth.uid() or
     p_entity_id is null or p_operation_id is null then
    raise exception using errcode = '42501', message = 'SYNC_NOT_AUTHORIZED';
  end if;
  target_table := case p_collection
    when 'farms' then 'farms' when 'paddocks' then 'paddocks'
    when 'animals' then 'animals' when 'movements' then 'animal_movements'
    when 'expenses' then 'expenses' else null end;
  if target_table is null then
    raise exception using errcode = '22023', message = 'SYNC_INVALID_COLLECTION';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_collection || ':' || p_entity_id::text, 0));
  -- Bypass RLS ONLY inside this narrowly scoped function, to reject another
  -- owner's ID rather than mistaking an RLS-hidden row for a nonexistent row.
  execute pg_catalog.format(
    'select user_id, deleted_at from public.%I where id = $1 for update', target_table)
    into actual_owner, previous_deleted_at using p_entity_id;
  if actual_owner is not null and actual_owner is distinct from p_owner_id then
    raise exception using errcode = '42501', message = 'SYNC_NOT_AUTHORIZED';
  end if;

  select * into terminal from public.sync_deletions
    where collection = p_collection and entity_id = p_entity_id;
  if terminal.entity_id is not null and terminal.user_id is distinct from p_owner_id then
    raise exception using errcode = '42501', message = 'SYNC_NOT_AUTHORIZED';
  end if;

  -- First accepted DELETE wins, even when the domain row does not exist yet.
  -- Advisory locking serializes normal writers of this identity. Do not INSERT
  -- on retries: ON CONFLICT would preserve the row but still consume a sequence.
  if terminal.entity_id is null then
    insert into public.sync_deletions(collection, entity_id, user_id, deleted_at, operation_id)
      values (p_collection, p_entity_id, p_owner_id,
        coalesce(previous_deleted_at, pg_catalog.clock_timestamp()), p_operation_id)
      returning * into terminal;
  end if;
  -- With an existing ledger, both same-ID and different-ID retries return the
  -- original operation/time. The trigger below must not replace p_operation_id.

  if actual_owner is not null and previous_deleted_at is null then
    execute pg_catalog.format(
      'update public.%I set deleted_at = $1 where id = $2 and user_id = $3', target_table)
      using terminal.deleted_at, p_entity_id, p_owner_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'collection', terminal.collection, 'entity_id', terminal.entity_id,
    'user_id', terminal.user_id, 'deleted_at', terminal.deleted_at,
    'operation_id', terminal.operation_id);
end;
$$;
revoke all on function public.sync_soft_delete(text, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.sync_soft_delete(text, uuid, uuid, uuid) to authenticated;

-- Backfill previously deleted identities; preserve all domain rows and timestamps.
-- Re-running keeps the first operation/time and does not duplicate ledger entries.
do $$
declare
  target_table text;
  entity_collection text;
begin
  foreach target_table in array array['farms','paddocks','animals','animal_movements','expenses']
  loop
    entity_collection := case when target_table = 'animal_movements'
      then 'movements' else target_table end;
    execute pg_catalog.format(
      'insert into public.sync_deletions(collection, entity_id, user_id, deleted_at, operation_id)
       select %L, d.id, d.user_id, d.deleted_at, pg_catalog.gen_random_uuid() from public.%I d
       where d.deleted_at is not null and not exists
         (select 1 from public.sync_deletions s where s.collection = %L and s.entity_id = d.id)
       on conflict (collection, entity_id) do nothing',
      entity_collection, target_table, entity_collection);
    execute pg_catalog.format('drop trigger if exists sync_terminal_identity on public.%I', target_table);
    execute pg_catalog.format(
      'create trigger sync_terminal_identity before insert or update on public.%I
       for each row execute function public.sync_guard_entity()', target_table);
    -- Existing permissive DELETE policies must not expose hard domain deletion.
    execute pg_catalog.format('drop policy if exists sync_no_hard_delete on public.%I', target_table);
    execute pg_catalog.format(
      'create policy sync_no_hard_delete on public.%I as restrictive
       for delete to anon, authenticated using (false)', target_table);
  end loop;
end;
$$;

commit;
