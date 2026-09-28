-- DELETE D1 ONLY. Explicit isolated manual application after review.
-- NEVER run a generic db push: the 20260926000100 hardening is SUSPENDED.
begin;
set local lock_timeout = '10s';
lock table public.paddocks, public.animals, public.animal_movements,
  public.sync_deletions in share row exclusive mode;

do $$
declare r record;
begin
  if current_user <> 'postgres' then raise exception 'D1_INSTALLER_MUST_BE_POSTGRES'; end if;
  if to_regclass('public.sync_movement_operations') is not null
    or exists(select from pg_proc where pronamespace='public'::regnamespace and
      proname in ('d1_lock_domain','d1_lock_statement','d1_assert_empty','d1_assert_paddock',
        'd1_guard_references','d1_can_receive_animals','sync_move_animal')) then
    raise exception 'D1_ALREADY_INSTALLED';
  end if;
  if exists(select from pg_trigger where tgrelid in ('public.paddocks'::regclass,
      'public.animals'::regclass,'public.animal_movements'::regclass)
      and tgname in ('d1_domain_gate','d1_reference_guard')) then
    raise exception 'D1_TRIGGER_COLLISION';
  end if;
  if not exists(select from pg_catalog.pg_timezone_names where name='America/Lima') then
    raise exception 'D1_BUSINESS_TIMEZONE_UNAVAILABLE';
  end if;
  if not exists(select from pg_proc where oid='public.sync_soft_delete(text,uuid,uuid,uuid)'::regprocedure
    and prosecdef and proowner=(select oid from pg_roles where rolname=current_user)) then
    raise exception 'D1_DELETE_A_OWNER_OR_CONTRACT_MISMATCH';
  end if;
  for r in select * from (values
    ('paddocks','id','uuid'),('paddocks','user_id','uuid'),('paddocks','deleted_at','timestamp with time zone'),
    ('paddocks','status','text'),('paddocks','required_rest_days','integer'),('paddocks','grazing_start_date','timestamp with time zone'),
    ('paddocks','last_grazing_end_date','timestamp with time zone'),('paddocks','planned_grazing_days','integer'),
    ('animals','id','uuid'),('animals','user_id','uuid'),('animals','paddock_id','uuid'),
    ('animals','deleted_at','timestamp with time zone'),
    ('animal_movements','id','uuid'),('animal_movements','user_id','uuid'),('animal_movements','animal_id','uuid'),
    ('animal_movements','from_paddock_id','uuid'),('animal_movements','to_paddock_id','uuid'),
    ('animal_movements','moved_at','timestamp with time zone'),('animal_movements','created_at','timestamp with time zone'),
    ('animal_movements','deleted_at','timestamp with time zone')) as x(tab,col,typ)
  loop
    if not exists(select from pg_attribute where attrelid=to_regclass('public.'||r.tab)
      and attname=r.col and not attisdropped and format_type(atttypid,atttypmod)=r.typ) then
      raise exception 'D1_COLUMN_MISMATCH: %.%',r.tab,r.col;
    end if;
  end loop;
  -- A new movement insert must not omit an unknown mandatory production column.
  if exists(select from pg_attribute a left join pg_attrdef d
      on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid='public.animal_movements'::regclass and a.attnum>0
      and not a.attisdropped and a.attnotnull and d.oid is null
      and a.attidentity='' and a.attgenerated=''
      and a.attname not in ('id','user_id','animal_id','from_paddock_id','to_paddock_id','moved_at','created_at')) then
    raise exception 'D1_UNKNOWN_REQUIRED_MOVEMENT_COLUMN';
  end if;
  if (select count(*) from pg_trigger where tgrelid in
    ('public.paddocks'::regclass,'public.animals'::regclass,'public.animal_movements'::regclass)
    and tgname='sync_terminal_identity' and tgenabled='O'
    and tgfoid='public.sync_guard_entity()'::regprocedure)<>3 then
    raise exception 'D1_TERMINAL_TRIGGER_MISMATCH';
  end if;
  if exists(select from public.animals a left join public.paddocks p on p.id=a.paddock_id
    where a.paddock_id is not null and (p.id is null or p.user_id is distinct from a.user_id
      or (a.deleted_at is null and p.deleted_at is not null))) then
    raise exception 'D1_EXISTING_ASSIGNMENT_CONFLICT';
  end if;
end $$;

-- Owner is postgres (installer guard above). Receipts survive domain deletion.
create table public.sync_movement_operations (
  movement_id uuid primary key,
  user_id uuid not null,
  animal_id uuid not null,
  from_paddock_id uuid,
  to_paddock_id uuid not null,
  moved_at timestamptz not null,
  plan_applied boolean not null,
  planned_grazing_days integer,
  result jsonb not null,
  completed_at timestamptz not null default clock_timestamp(),
  check ((plan_applied and planned_grazing_days is not null and planned_grazing_days>0)
    or (not plan_applied and planned_grazing_days is null))
);
alter table public.sync_movement_operations enable row level security;
revoke all on public.sync_movement_operations from public,anon,authenticated,service_role;
-- No client SELECT policy: retry response is supplied by the authenticated RPC.

create function public.d1_can_receive_animals(
  p_status text,p_required_rest_days integer,p_end timestamptz,p_reference timestamptz
) returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when p_status='Agotado' then false
    when p_status='En uso' then true
    when p_status='Descansando' then valid_plan and complete
    else not(valid_plan and not complete)
  end
  from (select valid_plan, coalesce(valid_plan and elapsed>=p_required_rest_days,false) as complete
    from (select
      coalesce(p_required_rest_days>0 and p_end is not null and p_reference is not null
        and (p_end at time zone 'America/Lima')::date <= (p_reference at time zone 'America/Lima')::date,false) as valid_plan,
      (p_reference at time zone 'America/Lima')::date - (p_end at time zone 'America/Lima')::date as elapsed
    ) days) eligibility;
$$;
revoke all on function public.d1_can_receive_animals(text,integer,timestamptz,timestamptz)
  from public,anon,authenticated,service_role;

create function public.d1_lock_domain() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode='0A000',message='SYNC_REQUIRES_READ_COMMITTED';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('delete-d1:movement-domain',0));
end $$;

create function public.d1_lock_statement() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.d1_lock_domain();
  return null;
end $$;

create function public.d1_assert_empty(p_id uuid,p_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if exists(select from public.animals where paddock_id=p_id and user_id=p_owner and deleted_at is null) then
    raise exception using errcode='P0001',message='SYNC_PADDOCK_OCCUPIED';
  end if;
end $$;

-- Historical reference validation does not equate physical existence with active state.
create function public.d1_assert_paddock(p_id uuid,p_owner uuid,p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.paddocks%rowtype;
begin
  if p_id is null then return; end if;
  select * into p from public.paddocks where id=p_id;
  if p.id is null or p.user_id is distinct from p_owner then
    raise exception using errcode='42501',message='SYNC_REFERENCE_NOT_AUTHORIZED';
  end if;
  if p_active and (p.deleted_at is not null or exists(select from public.sync_deletions
      where collection='paddocks' and entity_id=p_id)) then
    raise exception using errcode='P0001',message='SYNC_ENTITY_DELETED';
  end if;
end $$;

create function public.d1_guard_references() returns trigger
language plpgsql security definer set search_path = '' as $$
declare changed boolean; a public.animals%rowtype;
begin
  -- Statement gate is already held before any row lock; never acquire it here.
  if tg_table_name='paddocks' then
    if tg_op='UPDATE' and old.deleted_at is null and new.deleted_at is not null then
      perform public.d1_assert_empty(new.id,new.user_id);
    end if;
  elsif tg_table_name='animals' then
    changed := tg_op='INSERT';
    if tg_op='UPDATE' then changed := new.paddock_id is distinct from old.paddock_id; end if;
    perform public.d1_assert_paddock(new.paddock_id,new.user_id,changed);
  else
    select * into a from public.animals where id=new.animal_id;
    if a.id is null or a.user_id is distinct from new.user_id then
      raise exception using errcode='42501',message='SYNC_REFERENCE_NOT_AUTHORIZED';
    end if;
    changed := tg_op='INSERT';
    if tg_op='UPDATE' then
      changed := new.animal_id is distinct from old.animal_id
        or new.from_paddock_id is distinct from old.from_paddock_id
        or new.to_paddock_id is distinct from old.to_paddock_id
        or new.moved_at is distinct from old.moved_at;
    end if;
    if changed and (a.deleted_at is not null or exists(select from public.sync_deletions
      where collection='animals' and entity_id=a.id)) then
      raise exception using errcode='P0001',message='SYNC_ENTITY_DELETED';
    end if;
    perform public.d1_assert_paddock(new.from_paddock_id,new.user_id,false);
    perform public.d1_assert_paddock(new.to_paddock_id,new.user_id,changed);
  end if;
  return new;
end $$;

create trigger d1_domain_gate before insert or update on public.paddocks
for each statement execute function public.d1_lock_statement();
create trigger d1_domain_gate before insert or update on public.animals
for each statement execute function public.d1_lock_statement();
create trigger d1_domain_gate before insert or update on public.animal_movements
for each statement execute function public.d1_lock_statement();
create trigger d1_reference_guard before insert or update on public.paddocks
for each row execute function public.d1_guard_references();
create trigger d1_reference_guard before insert or update on public.animals
for each row execute function public.d1_guard_references();
create trigger d1_reference_guard before insert or update on public.animal_movements
for each row execute function public.d1_guard_references();
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

  if p_collection in ('paddocks','animals','movements') then
    perform public.d1_lock_domain();
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
  if terminal.entity_id is null and p_collection = 'paddocks' then
    perform public.d1_assert_empty(p_entity_id, p_owner_id);
  end if;
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


-- movement ID is the idempotency identity. Expected source is a CAS precondition.
-- Retry returns the original movement, never rewinds a later animal location.
create function public.sync_move_animal(
  p_owner_id uuid,p_animal_id uuid,p_movement_id uuid,p_from_paddock_id uuid,
  p_to_paddock_id uuid,p_moved_at timestamptz,p_planned_grazing_days integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  a public.animals%rowtype;
  m public.animal_movements%rowtype;
  destination_empty boolean;
  receipt public.sync_movement_operations%rowtype;
  destination public.paddocks%rowtype;
begin
  if auth.uid() is null or p_owner_id is distinct from auth.uid() then
    raise exception using errcode='42501',message='SYNC_NOT_AUTHORIZED';
  end if;
  if p_animal_id is null or p_movement_id is null or p_to_paddock_id is null or p_moved_at is null
    or p_from_paddock_id is not distinct from p_to_paddock_id
    or (p_planned_grazing_days is not null and p_planned_grazing_days<=0) then
    raise exception using errcode='22023',message='SYNC_INVALID_MOVE';
  end if;
  perform public.d1_lock_domain();
  select * into receipt from public.sync_movement_operations where movement_id=p_movement_id;
  if receipt.movement_id is not null then
    if receipt.user_id is distinct from p_owner_id then
      raise exception using errcode='42501',message='SYNC_NOT_AUTHORIZED';
    end if;
    if receipt.animal_id is distinct from p_animal_id
      or receipt.from_paddock_id is distinct from p_from_paddock_id
      or receipt.to_paddock_id is distinct from p_to_paddock_id
      or receipt.moved_at is distinct from p_moved_at
      or receipt.planned_grazing_days is distinct from
        (case when receipt.plan_applied then p_planned_grazing_days else null end) then
      raise exception using errcode='P0001',message='SYNC_MOVE_ID_CONFLICT';
    end if;
    return receipt.result;
  end if;
  select * into m from public.animal_movements where id=p_movement_id;
  if m.id is not null then
    if m.user_id is distinct from p_owner_id then
      raise exception using errcode='42501',message='SYNC_NOT_AUTHORIZED';
    end if;
    raise exception using errcode='P0001',message='SYNC_MOVE_LEGACY_CONFLICT';
  end if;
  if exists(select from public.sync_deletions where collection='movements' and entity_id=p_movement_id) then
    raise exception using errcode='P0001',message='SYNC_ENTITY_DELETED';
  end if;
  select * into a from public.animals where id=p_animal_id for update;
  if a.id is null or a.user_id is distinct from p_owner_id then
    raise exception using errcode='42501',message='SYNC_NOT_AUTHORIZED';
  end if;
  if a.deleted_at is not null or exists(select from public.sync_deletions
      where collection='animals' and entity_id=p_animal_id) then
    raise exception using errcode='P0001',message='SYNC_ENTITY_DELETED';
  end if;
  if a.paddock_id is distinct from p_from_paddock_id then
    raise exception using errcode='P0001',message='SYNC_MOVE_SOURCE_CONFLICT';
  end if;
  perform id from public.paddocks where id in (p_from_paddock_id,p_to_paddock_id) order by id for update;
  perform public.d1_assert_paddock(p_from_paddock_id,p_owner_id,true);
  perform public.d1_assert_paddock(p_to_paddock_id,p_owner_id,true);
  select * into destination from public.paddocks where id=p_to_paddock_id;
  if not public.d1_can_receive_animals(destination.status,destination.required_rest_days,
      destination.last_grazing_end_date,p_moved_at) then
    raise exception using errcode='P0001',message='SYNC_PADDOCK_NOT_AVAILABLE';
  end if;
  select not exists(select from public.animals where paddock_id=p_to_paddock_id
    and user_id=p_owner_id and deleted_at is null) into destination_empty;
  if destination_empty and p_planned_grazing_days is null then
    raise exception using errcode='22023',message='SYNC_GRAZING_DAYS_REQUIRED';
  end if;
  update public.animals set paddock_id=p_to_paddock_id where id=p_animal_id;
  insert into public.animal_movements(id,user_id,animal_id,from_paddock_id,to_paddock_id,moved_at,created_at)
    values(p_movement_id,p_owner_id,p_animal_id,p_from_paddock_id,p_to_paddock_id,p_moved_at,p_moved_at)
    returning * into m;
  -- Dates come from the real supplied movement, never from deletion or a fabricated event.
  if p_from_paddock_id is not null then
    if exists(select from public.animals where paddock_id=p_from_paddock_id
        and user_id=p_owner_id and deleted_at is null) then
      update public.paddocks set status='En uso' where id=p_from_paddock_id;
    else
      update public.paddocks set status='Descansando',grazing_start_date=null,
        planned_grazing_days=null,last_grazing_end_date=p_moved_at where id=p_from_paddock_id;
    end if;
  end if;
  update public.paddocks set status='En uso',last_grazing_end_date=null,
    grazing_start_date=case when destination_empty then p_moved_at else grazing_start_date end,
    planned_grazing_days=case when destination_empty then p_planned_grazing_days else planned_grazing_days end
    where id=p_to_paddock_id;
  insert into public.sync_movement_operations(movement_id,user_id,animal_id,from_paddock_id,
    to_paddock_id,moved_at,plan_applied,planned_grazing_days,result)
    values(p_movement_id,p_owner_id,p_animal_id,p_from_paddock_id,p_to_paddock_id,p_moved_at,
      destination_empty,case when destination_empty then p_planned_grazing_days else null end,pg_catalog.to_jsonb(m));
  return pg_catalog.to_jsonb(m);
end $$;

revoke all on function public.d1_lock_domain(),public.d1_lock_statement(),
 public.d1_assert_empty(uuid,uuid),public.d1_assert_paddock(uuid,uuid,boolean),
 public.d1_guard_references() from public,anon,authenticated;
revoke all on function public.sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer)
 from public,anon,authenticated;
grant execute on function public.sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer) to authenticated;
commit;
