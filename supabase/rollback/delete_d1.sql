-- D1 rollback ONLY, never the suspended DELETE E hardening.
-- Stop movement clients first. This restores old behavior including its lack
-- of occupied-paddock protection. No ledger/domain data is removed.
begin;
set local lock_timeout = '10s';
lock table public.paddocks,public.animals,public.animal_movements,public.sync_deletions in share row exclusive mode;
-- Completed receipts must never be discarded to make rollback convenient.
do $$ begin
  if exists(select from public.sync_movement_operations) then
    raise exception 'D1_ROLLBACK_HAS_COMPLETED_OPERATIONS';
  end if;
end $$;
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


drop trigger d1_domain_gate on public.paddocks;
drop trigger d1_domain_gate on public.animals;
drop trigger d1_domain_gate on public.animal_movements;
drop trigger d1_reference_guard on public.paddocks;
drop trigger d1_reference_guard on public.animals;
drop trigger d1_reference_guard on public.animal_movements;
drop function public.sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer);
drop function public.d1_guard_references();
drop function public.d1_lock_statement();
drop function public.d1_assert_paddock(uuid,uuid,boolean);
drop function public.d1_assert_empty(uuid,uuid);
drop function public.d1_lock_domain();
drop function public.d1_can_receive_animals(text,integer,timestamptz,timestamptz);
drop table public.sync_movement_operations;
commit;
