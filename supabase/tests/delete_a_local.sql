-- LOCAL-ONLY fixture, NOT a migration and NEVER for the Supabase SQL editor.
-- Run psql -X -v ON_ERROR_STOP=1 -d mi_finca_delete_a_test -f this_file.sql
-- Requires a NEW disposable PostgreSQL >= 15 database and an administrative role.
\set ON_ERROR_STOP on
DO $$ begin
  if current_database() <> 'mi_finca_delete_a_test' or
     to_regclass('public.animals') is not null or
     to_regclass('auth.users') is not null then
    raise exception 'Use a NEW empty local database named mi_finca_delete_a_test';
  end if;
end $$;
DO $$ begin
  if not exists(select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists(select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname = 'service_role') then create role service_role bypassrls; end if;
end $$;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth, public to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
insert into auth.users values
 ('00000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-000000000002');
DO $$ declare t text; begin
  foreach t in array array['farms','paddocks','animals','animal_movements','expenses'] loop
    execute format('create table public.%I (id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade, name text, deleted_at timestamptz, updated_at timestamptz default now())', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant select, delete on public.%I to anon', t);
    -- Deliberately permissive legacy fixtures: the restrictive policy alone
    -- must block DELETE, rather than a missing grant or invisible rows.
    execute format('create policy legacy_anon_select on public.%I for select to anon using (true)', t);
    execute format('create policy legacy_anon_delete on public.%I for delete to anon using (true)', t);
    execute format('create policy owner_all on public.%I to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
    execute format('insert into public.%I(id, user_id, name) values ($1, $2, $3)', t)
      using '10000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'existing';
  end loop;
end $$;
insert into public.expenses(id,user_id,name,deleted_at) values
 ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001','previously deleted','2020-01-01T00:00:00Z');
-- Reapplication must preserve existing rows and original tombstone metadata.
create temp table first_domain as
select 'farms' as collection, to_jsonb(d) as payload from public.farms d union all
select 'paddocks', to_jsonb(d) from public.paddocks d union all
select 'animals', to_jsonb(d) from public.animals d union all
select 'movements', to_jsonb(d) from public.animal_movements d union all
select 'expenses', to_jsonb(d) from public.expenses d;
\ir ../migrations/20260924000200_delete_a_infrastructure.sql
create temp table first_sequence as select last_value, is_called from public.sync_deletions_sequence_seq;
create temp table first_ledger as select * from public.sync_deletions;
\ir ../migrations/20260924000200_delete_a_infrastructure.sql
DO $$ begin
 if (select count(*) from public.sync_deletions) <> 1 or
    (select deleted_at from public.sync_deletions) <> '2020-01-01T00:00:00Z'::timestamptz then
   raise exception 'Backfill must preserve original timestamp and create one ledger';
 end if;
 if exists(select * from first_sequence except select last_value,is_called from public.sync_deletions_sequence_seq) then
   raise exception 'Rerun consumed identity sequence';
 end if;
 if exists(select * from first_ledger except select * from public.sync_deletions) then
   raise exception 'Reapplication changed ledger';
 end if;
end $$;
DO $$ declare t text; c text; actual jsonb; expected jsonb; begin
 foreach t in array array['farms','paddocks','animals','animal_movements','expenses'] loop
   c := case when t='animal_movements' then 'movements' else t end;
   execute format('select jsonb_agg(to_jsonb(d) order by id) from public.%I d',t) into actual;
   select jsonb_agg(payload order by payload->>'id') into expected from first_domain where collection=c;
   if actual is distinct from expected then raise exception 'Rerun changed domain rows'; end if;
 end loop;
end $$;
-- Exact client role scope; no PUBLIC/service/admin inclusion.
DO $$ begin
 if (select count(*) from pg_policies where schemaname='public'
     and tablename in ('farms','paddocks','animals','animal_movements','expenses')
     and policyname='sync_no_hard_delete' and permissive='RESTRICTIVE' and cmd='DELETE'
     and roles @> array['anon','authenticated']::name[] and cardinality(roles)=2) <> 5 then
   raise exception 'Hard-delete policy must target exactly anon and authenticated';
 end if;
 if not has_function_privilege('authenticated','public.sync_soft_delete(text,uuid,uuid,uuid)','EXECUTE') or
    has_function_privilege('anon','public.sync_soft_delete(text,uuid,uuid,uuid)','EXECUTE') then
   raise exception 'Soft-delete RPC client access must be authenticated only';
 end if;
end $$;
set role anon;
select set_config('request.jwt.claim.sub','',false);
DO $$ declare t text; before_count bigint; after_count bigint; removed bigint; begin
 foreach t in array array['farms','paddocks','animals','animal_movements','expenses'] loop
   if not has_table_privilege('anon',format('public.%I',t),'DELETE') then
     raise exception 'Fixture must grant DELETE to anon';
   end if;
   execute format('select count(*) from public.%I',t) into before_count;
   if before_count=0 then raise exception 'Fixture must expose rows to anon SELECT'; end if;
   execute format('delete from public.%I',t);
   get diagnostics removed = row_count;
   execute format('select count(*) from public.%I',t) into after_count;
   if removed<>0 or after_count<>before_count then raise exception 'anon hard DELETE was allowed'; end if;
 end loop;
 begin
   perform public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000001',
     '00000000-0000-4000-8000-000000000001',gen_random_uuid());
   raise exception using errcode='XX000',message='anon invoked soft-delete RPC';
 exception when sqlstate '42501' then null;
 end;
end $$;
reset role;
-- Foreign physical row must never acquire A's tombstone.
insert into public.animals(id,user_id,name) values
 ('10000000-0000-4000-8000-000000000009','00000000-0000-4000-8000-000000000002','B-private');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ declare c text; t text; first_result jsonb; second_result jsonb; count_rows int; op uuid; seq bigint; begin
 foreach c in array array['farms','paddocks','animals','movements','expenses'] loop
   t := case when c = 'movements' then 'animal_movements' else c end;
   -- Active INSERT ... ON CONFLICT must still perform a real payload update.
   execute format('insert into public.%I(id,user_id,name) values ($1,$2,$3) on conflict(id) do update set name=excluded.name',t)
     using '10000000-0000-4000-8000-000000000001'::uuid, auth.uid(), 'active upsert';
   execute format('select count(*) from public.%I where name=$1 and deleted_at is null',t) into count_rows using 'active upsert';
   if count_rows <> 1 then raise exception 'Active UPSERT failed'; end if;
   op := gen_random_uuid();
   first_result := public.sync_soft_delete(c,'10000000-0000-4000-8000-000000000001',auth.uid(),op);
   if first_result->>'operation_id' <> op::text then raise exception 'Trigger replaced RPC operationId'; end if;
   select sequence into seq from public.sync_deletions where collection=c and entity_id='10000000-0000-4000-8000-000000000001';
   second_result := public.sync_soft_delete(c,'10000000-0000-4000-8000-000000000001',auth.uid(),op);
   if first_result <> second_result then raise exception 'Same operation retry changed tombstone'; end if;
   second_result := public.sync_soft_delete(c,'10000000-0000-4000-8000-000000000001',auth.uid(),gen_random_uuid());
   if first_result <> second_result then raise exception 'Different operation retry changed tombstone'; end if;
   if seq <> (select sequence from public.sync_deletions where collection=c and entity_id='10000000-0000-4000-8000-000000000001') then raise exception 'Retry changed row sequence'; end if;
   execute format('select count(*) from public.%I where deleted_at is not null and name = $1',t) into count_rows using 'active upsert';
   if count_rows <> 1 then raise exception 'Domain payload lost'; end if;
   begin
     execute format('insert into public.%I(id,user_id,name) values ($1,$2,$3) on conflict(id) do update set name = excluded.name',t)
       using '10000000-0000-4000-8000-000000000001'::uuid,auth.uid(),'stale app';
     raise exception using errcode='XX000',message='Old UPSERT revived ID';
   exception when sqlstate 'P0001' then
     if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if; end;
   begin
     execute format('update public.%I set deleted_at = null',t);
     raise exception using errcode='XX000',message='UPDATE revived ID';
   exception when sqlstate 'P0001' then
     if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if; end;
   execute format('delete from public.%I',t);
   execute format('select count(*) from public.%I where id = $1',t) into count_rows
     using '10000000-0000-4000-8000-000000000001'::uuid;
   if count_rows <> 1 then raise exception 'Hard DELETE was allowed'; end if;
 end loop;
 -- A cannot delete or reserve an existing B identity, even via SECURITY DEFINER.
 begin
   perform public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000009',auth.uid(),gen_random_uuid());
   raise exception using errcode='XX000',message='A deleted B';
 exception when sqlstate '42501' then
   if sqlerrm <> 'SYNC_NOT_AUTHORIZED' then raise; end if;
 end;
 -- Identity deleted before it was ever uploaded.
 perform public.sync_soft_delete('expenses','10000000-0000-4000-8000-000000000003',auth.uid(),gen_random_uuid());
 begin
   insert into public.expenses(id,user_id,name) values ('10000000-0000-4000-8000-000000000003',auth.uid(),'late CREATE');
   raise exception using errcode='XX000',message='Late CREATE revived missing ID';
 exception when sqlstate 'P0001' then
     if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if; end;
 -- Direct soft-delete must use the server clock, not the phone-supplied year.
 insert into public.expenses(id,user_id,name) values ('10000000-0000-4000-8000-000000000004',auth.uid(),'direct');
 update public.expenses set deleted_at = '1990-01-01T00:00:00Z' where id = '10000000-0000-4000-8000-000000000004';
 if exists(select 1 from public.expenses where id = '10000000-0000-4000-8000-000000000004' and deleted_at = '1990-01-01T00:00:00Z') then
   raise exception 'Phone clock accepted';
 end if;
end $$;
-- Direct legacy animal deletion: payload+delete must fail atomically.
DO $$ declare original public.sync_deletions%rowtype; reply jsonb; begin
 insert into public.animals(id,user_id,name) values
 ('10000000-0000-4000-8000-000000000005',auth.uid(),'legacy');
 begin
   update public.animals set deleted_at=now(),name='otro' where id='10000000-0000-4000-8000-000000000005';
   raise exception using errcode='XX000',message='Payload change hidden inside delete';
 exception when sqlstate 'P0001' then
   if sqlerrm <> 'SYNC_DELETE_ONLY' then raise; end if;
 end;
 if exists(select 1 from public.sync_deletions where entity_id='10000000-0000-4000-8000-000000000005') then raise exception 'Rejected update created ledger'; end if;
 update public.animals set deleted_at=now() where id='10000000-0000-4000-8000-000000000005';
 select * into strict original from public.sync_deletions where collection='animals' and entity_id='10000000-0000-4000-8000-000000000005';
 if original.operation_id is null or original.deleted_at is distinct from
   (select deleted_at from public.animals where id=original.entity_id) then raise exception 'Invalid legacy ledger'; end if;
 reply := public.sync_soft_delete('animals',original.entity_id,auth.uid(),gen_random_uuid());
 if reply->>'operation_id' <> original.operation_id::text or
   (reply->>'deleted_at')::timestamptz <> original.deleted_at or
   (select sequence from public.sync_deletions where collection='animals' and entity_id=original.entity_id) <> original.sequence then raise exception 'RPC modified legacy tombstone'; end if;
 begin
   update public.animals set name='post-delete' where id=original.entity_id;
   raise exception using errcode='XX000',message='Deleted payload modified';
 exception when sqlstate 'P0001' then
   if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $$ begin
 if exists(select 1 from public.sync_deletions) then raise exception 'RLS leaked another account'; end if;
 -- B cannot INSERT an identity A reserved while no physical row existed.
 begin
   insert into public.expenses(id,user_id,name) values
     ('10000000-0000-4000-8000-000000000003',auth.uid(),'B collision');
   raise exception using errcode='XX000',message='B recreated A terminal identity';
 exception when sqlstate 'P0001' then
   if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if;
 end;
 perform public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000009',auth.uid(),gen_random_uuid());
 if (select count(*) from public.sync_deletions) <> 1 then raise exception 'B own tombstone unavailable'; end if;
 begin
   perform public.sync_soft_delete('expenses','10000000-0000-4000-8000-000000000001',auth.uid(),gen_random_uuid());
   raise exception using errcode='XX000',message='Cross-owner delete accepted';
 exception when sqlstate '42501' then null; end;
 begin
   perform public.sync_soft_delete('expenses','10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',gen_random_uuid());
   raise exception using errcode='XX000',message='Spoofed owner accepted';
 exception when sqlstate '42501' then null; end;
 begin
   delete from public.sync_deletions;
   raise exception using errcode='XX000',message='Ledger mutation allowed';
 exception when sqlstate '42501' then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ begin
 if exists(select 1 from public.sync_deletions where user_id <> auth.uid()) then raise exception 'A can read B tombstone'; end if;
end $$;
reset role;
-- Service/admin HARD DELETE is not blocked by the client-only policy (anon/authenticated).
-- INSERT/UPDATE terminal guards still apply to admins; no implicit restore path.
grant usage on schema public to service_role;
grant select,delete on public.animals to service_role;
set role service_role;
DO $$ declare n int; begin
 delete from public.animals where id='10000000-0000-4000-8000-000000000009';
 get diagnostics n = row_count;
 if n <> 1 then raise exception 'Service role hard DELETE blocked'; end if;
end $$;
reset role;
DO $$ begin
 if (select last_value from public.sync_deletions_sequence_seq) <> (select count(*) from public.sync_deletions) then raise exception 'Retry/trigger consumed extra sequence values in this rollback-free allocation fixture'; end if;
 if not exists(select 1 from public.sync_deletions where entity_id='10000000-0000-4000-8000-000000000009') then raise exception 'Admin hard delete purged terminal identity'; end if;
 -- Existing permissive policies must remain installed.
 if (select count(*) from pg_policies where schemaname='public' and policyname='owner_all') <> 5 then raise exception 'Legacy policies removed'; end if;
 if (select count(*) from pg_policies where schemaname='public' and policyname in ('legacy_anon_select','legacy_anon_delete')) <> 10 then raise exception 'Legacy anon policies removed'; end if;
end $$;
-- Rerun also after RPC, legacy deletion and an administrative physical deletion.
create temp table final_ledger as select * from public.sync_deletions;
create temp table final_sequence as select last_value,is_called from public.sync_deletions_sequence_seq;
\ir ../migrations/20260924000200_delete_a_infrastructure.sql
DO $$ begin
 if exists(select * from final_ledger except select * from public.sync_deletions) or
    exists(select * from public.sync_deletions except select * from final_ledger) then raise exception 'Final rerun changed terminal identities'; end if;
 if exists(select * from final_sequence except select last_value,is_called from public.sync_deletions_sequence_seq) then raise exception 'Final rerun consumed sequence'; end if;
end $$;
-- Fixed transaction snapshots must fail closed, rather than miss a concurrent ledger.
begin isolation level repeatable read;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$ begin
 begin
   perform public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000008',auth.uid(),gen_random_uuid());
   raise exception using errcode='XX000',message='Unsupported snapshot accepted by RPC';
 exception when sqlstate '0A000' then
   if sqlerrm <> 'SYNC_REQUIRES_READ_COMMITTED' then raise; end if;
 end;
 begin
   insert into public.animals(id,user_id,name) values ('10000000-0000-4000-8000-000000000008',auth.uid(),'fixed snapshot');
   raise exception using errcode='XX000',message='Unsupported snapshot accepted by trigger';
 exception when sqlstate '0A000' then
   if sqlerrm <> 'SYNC_REQUIRES_READ_COMMITTED' then raise; end if;
 end;
end $$;
rollback;
select 'DELETE A local SQL assertions passed' as result;
