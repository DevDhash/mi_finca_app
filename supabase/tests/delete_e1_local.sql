-- LOCAL DISPOSABLE DATABASE ONLY. Never run in Supabase SQL Editor.
-- PostgreSQL fixture, not the Supabase Storage HTTP service or production schema.
\set ON_ERROR_STOP on
DO $$ begin
 if current_database()<>'mi_finca_delete_e1_test' or to_regclass('public.animals') is not null
    or to_regclass('auth.users') is not null then raise exception 'Requires NEW disposable mi_finca_delete_e1_test'; end if;
end $$;
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema storage;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as
$$ select nullif(current_setting('request.jwt.claim.role',true),'') $$;
create function storage.foldername(text) returns text[] language sql immutable as
$$ select (string_to_array($1,'/'))[1:cardinality(string_to_array($1,'/'))-1] $$;
grant usage on schema public,auth,storage to anon,authenticated,service_role;
create function public.test_id(n integer) returns uuid language sql immutable as
$$ select ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function public.test_path(owner_n integer,animal_n integer,file_n integer default 100) returns text language sql immutable as
$$ select public.test_id(owner_n)::text||'/'||public.test_id(animal_n)::text||'/'||public.test_id(file_n)::text||'.jpg' $$;
create table public.test_results(n integer primary key,label text not null);
grant select,insert on public.test_results to anon,authenticated,service_role;
create function public.test_ok(n integer,label text,ok boolean) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL %: %',n,label; end if;
 insert into public.test_results values(n,label); raise notice 'PASS %: %',n,label;
end $$;
create table auth.users(id uuid primary key);
insert into auth.users values(test_id(1)),(test_id(2));
create function public.fixture_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=clock_timestamp(); return new; end $$;
do $$ declare t text; begin
 foreach t in array array['farms','paddocks','animals','animal_movements','expenses'] loop
  execute format('create table public.%I(id uuid primary key,user_id uuid not null references auth.users(id),name text,deleted_at timestamptz,updated_at timestamptz default now())',t);
  execute format('alter table public.%I enable row level security',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('create policy fixture_own on public.%I to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid())',t);
  execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function public.fixture_updated_at()',t,t);
 end loop;
end $$;
alter table public.animals add column photo_path text;
alter table public.animal_movements add column animal_id uuid references public.animals(id);
insert into public.animals(id,user_id,name,deleted_at)
select test_id(n),test_id(1),'terminal '||n,'2020-01-01'::timestamptz from generate_series(10,13)n;
insert into public.animals(id,user_id,name) values(test_id(20),test_id(1),'active');
insert into public.animal_movements(id,user_id,name,animal_id) values(test_id(50),test_id(1),'historical',test_id(10));
create table storage.buckets(id text primary key,name text not null,public boolean not null default false);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text not null,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant select,insert,update,delete on storage.objects to anon,authenticated;
-- Deliberately broad legacy grants/policy: restrictive policies must win.
create policy fixture_permissive_all on storage.objects for all to anon,authenticated using(true) with check(true);
-- Apply EVERY versioned migration in chronological order, on top of explicit base fixture.
\ir ../migrations/20260924000100_animal_photos_foto_a.sql
update public.animals set remote_photo_path=test_path(1,10,102) where id=test_id(10);
update public.animals set remote_photo_path=test_path(1,12) where id=test_id(12);
update public.animals set remote_photo_path=test_path(1,13) where id=test_id(13);
insert into storage.objects(bucket_id,name) values
 ('animal-photos',test_path(1,10,100)),('animal-photos',test_path(1,10,101)),('animal-photos',test_path(1,10,102)),
 ('animal-photos',test_path(1,12)),('animal-photos',test_path(1,13));
\ir ../migrations/20260924000200_delete_a_infrastructure.sql
-- Deployed service role has administrative SELECT; DELETE A does not grant it explicitly.
grant select on public.sync_deletions to service_role;
create temp table before_animals as select * from public.animals;
create temp table before_movements as select * from public.animal_movements;
create temp table before_ledger as select * from public.sync_deletions;
create temp table before_policies as select * from pg_policies where schemaname='storage' and policyname<>'animal_photos_insert_guard';
create temp table before_objects as select * from storage.objects;
create temp table before_functions as select oid,pg_get_functiondef(oid) as definition from pg_proc where proname in ('sync_soft_delete','sync_guard_entity','fixture_updated_at');
\ir ../migrations/20260924000300_animal_photo_cleanup_contract.sql
\if :{?rollback_roundtrip}
\ir delete_e1_rollback_local.sql
-- Verify the intermediate rollback, before reinstalling anything.
select test_ok(51,'rollback removes E1 objects',
 to_regclass('public.animal_photo_cleanup_jobs') is null
 and to_regprocedure('public.animal_photo_insert_allowed(text)') is null);
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',test_id(1)::text,true);
select set_config('request.jwt.claim.role','authenticated',true);
-- Terminal upload MUST work under the restored FOTO A contract.
insert into storage.objects(bucket_id,name) values('animal-photos',test_path(1,10,999));
rollback;
select test_ok(52,'restored FOTO A accepts terminal upload; probe rolled back',
 not exists(select 1 from storage.objects where name=test_path(1,10,999)));
\if :{?preflight}
select set_config('test.e1_preflight', :'preflight', false);
do $$ declare code text; begin
 -- Execute the exact DO block extracted from the migration by the runner.
 execute current_setting('test.e1_preflight');
 alter policy animal_photos_no_delete on storage.objects using ((("bucket_id") <> ('animal-photos'::text)));
 execute current_setting('test.e1_preflight');
 perform test_ok(53,'actual preflight accepts baseline and cosmetic syntax',true);
 foreach code in array array[
  'bucket_id <> ''animal-photos'' or true',
  'bucket_id <> ''animal- photos''',
  'bucket_id = ''animal-photos'''] loop
  execute 'alter policy animal_photos_no_delete on storage.objects using ('||code||')';
  begin
   execute current_setting('test.e1_preflight');
   raise exception 'Drift accepted: %',code;
  exception when sqlstate 'P0001' then
   if sqlerrm<>'E1_STORAGE_GUARD_BASELINE_MISMATCH' then raise; end if;
  end;
 end loop;
 alter policy animal_photos_no_delete on storage.objects using(bucket_id<>'animal-photos');
 perform test_ok(54,'actual preflight rejects broadened guard and changed literals',true);
end $$;
\endif
\ir ../migrations/20260924000300_animal_photo_cleanup_contract.sql
\endif
select test_ok(12,'backfill four terminal identities',(select count(*)=4 and bool_and(status='pending' and attempt_count=0 and generation=0 and uncertain_failure_count=0 and lease_token is null and lease_expires_at is null and last_attempt_at is null and verified_empty_at is null) from public.animal_photo_cleanup_jobs));
select test_ok(14,'zero objects still has job',exists(select 1 from public.animal_photo_cleanup_jobs where animal_id=test_id(11)));
select test_ok(15,'three objects one job',(select count(*)=1 from public.animal_photo_cleanup_jobs where animal_id=test_id(10)));
select test_ok(23,'movements unchanged',not exists((select * from before_movements except select * from public.animal_movements) union all (select * from public.animal_movements except select * from before_movements)));
select test_ok(24,'animal payload and photo reference unchanged',not exists((select * from before_animals except select * from public.animals) union all (select * from public.animals except select * from before_animals)));
select test_ok(25,'all five Storage metadata rows unchanged',not exists((select * from before_objects except select * from storage.objects) union all (select * from storage.objects except select * from before_objects)));
select test_ok(35,'DELETE A and timestamp functions unchanged',not exists(select 1 from before_functions where definition<>pg_get_functiondef(oid)));
select test_ok(55,'ledger unchanged by E1 and rollback roundtrip',not exists(
 (select * from before_ledger except select * from public.sync_deletions)
 union all (select * from public.sync_deletions except select * from before_ledger)));
select test_ok(56,'other Storage policies unchanged',not exists(
 (select * from before_policies except select * from pg_policies where schemaname='storage' and policyname<>'animal_photos_insert_guard')
 union all (select * from pg_policies where schemaname='storage' and policyname<>'animal_photos_insert_guard' except select * from before_policies)));
select test_ok(57,'all five E1 functions INVOKER and empty search_path',
 (select count(*)=5 and bool_and(not prosecdef and proconfig=array['search_path=""'])
 from pg_proc where pronamespace='public'::regnamespace and proname in
 ('animal_photo_insert_allowed','animal_photo_cleanup_job_guard','discover_animal_photo_cleanup_jobs','claim_animal_photo_cleanup_job','finish_animal_photo_cleanup_attempt')));
create temp table before_jobs as select * from public.animal_photo_cleanup_jobs;
set role service_role;
select public.discover_animal_photo_cleanup_jobs(1);
select public.discover_animal_photo_cleanup_jobs(1000);
reset role;
select test_ok(13,'discovery preserves complete existing job snapshots',not exists((select * from before_jobs except select * from public.animal_photo_cleanup_jobs) union all (select * from public.animal_photo_cleanup_jobs except select * from before_jobs)));

-- Actual INSERT policy on a physical storage.objects fixture, not helper-only tests.
create function public.test_upload(n integer,label text,p text,allowed boolean) returns void language plpgsql as $$
declare succeeded boolean:=false;
begin
 if public.animal_photo_insert_allowed(p) is distinct from allowed then raise exception 'Helper mismatch %',n; end if;
 begin
  insert into storage.objects(bucket_id,name) values('animal-photos',p);
  succeeded:=true;
 exception when insufficient_privilege then succeeded:=false;
 end;
 perform public.test_ok(n,label,succeeded=allowed);
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub',test_id(1)::text,false);
select set_config('request.jwt.claim.role','authenticated',false);
select test_upload(1,'new absent identity policy permits bytes',test_path(1,21),true);
select test_upload(2,'active animal policy permits bytes',test_path(1,20),true);
select test_upload(3,'terminal policy rejects bytes',test_path(1,12,103),false);
select test_upload(4,'terminal NULL reference rejected',test_path(1,11),false);
select test_upload(5,'terminal stale reference rejected',test_path(1,10,104),false);
select test_upload(6,'foreign owner rejected',test_path(2,21),false);
select test_upload(7,'invalid UUID no cast exception',test_id(1)::text||'/garbage/'||test_id(100)||'.jpg',false);
select test_upload(8,'incomplete path',test_id(1)::text||'/',false);
select test_upload(9,'extra path segments',test_path(1,21)||'/extra',false);
do $$ declare n bigint; begin
 delete from storage.objects where bucket_id='animal-photos'; get diagnostics n=row_count;
 perform test_ok(10,'DELETE restrictive guard wins over broad policy',n=0);
 update storage.objects set name=name||'.other' where bucket_id='animal-photos'; get diagnostics n=row_count;
 perform test_ok(11,'UPDATE restrictive guard wins over broad policy',n=0);
end $$;
do $$ declare q text; n int:=16; begin
 foreach q in array array[
  'insert into public.animal_photo_cleanup_jobs default values',
  'update public.animal_photo_cleanup_jobs set status=''pending''',
  'delete from public.animal_photo_cleanup_jobs',
  'select * from public.animal_photo_cleanup_jobs'] loop
  begin execute q; raise exception 'Unexpected job access';
  exception when insufficient_privilege then perform test_ok(n,'authenticated job access denied',true); end;
  n:=n+1;
 end loop;
end $$;
select test_ok(31,'INVOKER sees own ledger',exists(select 1 from public.sync_deletions where entity_id=test_id(10)) and not public.animal_photo_insert_allowed(test_path(1,10,110)));
select test_ok(34,'bytes before first UPSERT preserved',not exists(select 1 from public.animals where id=test_id(21)) and exists(select 1 from storage.objects where name=test_path(1,21)));
do $$ declare first jsonb; seq bigint; begin
 first:=public.sync_soft_delete('animals',test_id(20),auth.uid(),test_id(200));
 select sequence into seq from public.sync_deletions where collection='animals' and entity_id=test_id(20);
 perform test_ok(21,'same and different operation retries stable',
  first=public.sync_soft_delete('animals',test_id(20),auth.uid(),test_id(200))
  and first=public.sync_soft_delete('animals',test_id(20),auth.uid(),test_id(201))
  and seq=(select sequence from public.sync_deletions where collection='animals' and entity_id=test_id(20)));
 begin
  insert into public.animals(id,user_id,name) values(test_id(20),auth.uid(),'resurrect') on conflict(id) do update set name=excluded.name;
  raise exception 'Resurrection accepted';
 exception when sqlstate 'P0001' then
  if sqlerrm<>'SYNC_ENTITY_DELETED' then raise; end if;
  perform test_ok(22,'stale UPSERT terminal rejected',true);
 end;
end $$;
select set_config('request.jwt.claim.sub',test_id(2)::text,false);
select test_ok(32,'B cannot see A ledger; helper cannot probe foreign namespace',
 not exists(select 1 from public.sync_deletions) and not public.animal_photo_insert_allowed(test_path(1,10))
 and public.animal_photo_insert_allowed(test_path(2,10)));
-- Same animal UUID in OWN namespace says nothing about another owner's ledger.
select set_config('request.jwt.claim.sub',test_id(1)::text,false);
do $$ declare p text; begin
 foreach p in array array[null,'','/',test_id(1)::text||'//x.jpg',test_id(1)::text||'/../../x.jpg',
  test_id(1)::text||'/not-a-uuid/x.jpg',test_path(1,21)||'/',test_id(1)::text||'/'||test_id(21)||'/x.jpg',
  test_id(1)::text||'/AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/'||test_id(100)||'.jpg'] loop
  if public.animal_photo_insert_allowed(p) then raise exception 'Malformed path accepted'; end if;
  begin insert into storage.objects(bucket_id,name) values('animal-photos',p); raise exception 'Malformed policy insert accepted';
  exception when insufficient_privilege then null; end;
 end loop;
 perform test_ok(33,'malformed helper and policy never unsafe cast',true);
end $$;
set role anon;
select set_config('request.jwt.claim.role','anon',false);
select set_config('request.jwt.claim.sub','',false);
do $$ declare q text; begin
 if public.animal_photo_insert_allowed(test_path(1,21)) then raise exception 'anon helper accepted'; end if;
 begin insert into storage.objects(bucket_id,name) values('animal-photos',test_path(1,21,111)); raise exception 'anon upload accepted';
 exception when insufficient_privilege then null; end;
 foreach q in array array['select * from public.animal_photo_cleanup_jobs','insert into public.animal_photo_cleanup_jobs default values',
 'update public.animal_photo_cleanup_jobs set status=''pending''','delete from public.animal_photo_cleanup_jobs',
 'select public.claim_animal_photo_cleanup_job()','select public.discover_animal_photo_cleanup_jobs()'] loop
  begin execute q; raise exception 'anon job access'; exception when insufficient_privilege then null; end;
 end loop;
 perform test_ok(20,'anon no jobs, RPC or upload',true);
end $$;
reset role;
-- Keep exactly one eligible fixture job, without touching any real dataset.
update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()+interval '1 day';
update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=test_id(10);
set role service_role;
do $$ declare old_job public.animal_photo_cleanup_jobs; new_job public.animal_photo_cleanup_jobs; reply boolean; begin
 select * into strict old_job from public.claim_animal_photo_cleanup_job();
 perform test_ok(36,'second sequential claim sees lease',not exists(select 1 from public.claim_animal_photo_cleanup_job()));
 update public.animal_photo_cleanup_jobs set last_attempt_at=clock_timestamp()-interval '3 minutes',lease_expires_at=clock_timestamp()-interval '1 second' where animal_id=old_job.animal_id;
 perform test_ok(37,'expired lease cannot ACK before reclaim',not public.finish_animal_photo_cleanup_attempt(old_job.animal_id,old_job.lease_token,old_job.generation,'observed_empty'));
 select * into strict new_job from public.claim_animal_photo_cleanup_job();
 perform test_ok(27,'expired lease reclaimed',new_job.generation=old_job.generation+1 and new_job.lease_token<>old_job.lease_token);
 perform test_ok(28,'stale token or generation cannot ACK',
  not public.finish_animal_photo_cleanup_attempt(old_job.animal_id,old_job.lease_token,old_job.generation,'observed_empty')
  and not public.finish_animal_photo_cleanup_attempt(new_job.animal_id,new_job.lease_token,old_job.generation,'observed_empty'));
 reply:=public.finish_animal_photo_cleanup_attempt(new_job.animal_id,new_job.lease_token,new_job.generation,'observed_empty');
 if not reply then raise exception 'Valid ACK rejected'; end if;
 update public.animal_photo_cleanup_jobs set verified_empty_at=clock_timestamp()-interval '2 minutes',next_verification_at=clock_timestamp()-interval '1 minute' where animal_id=new_job.animal_id;
 select * into strict new_job from public.claim_animal_photo_cleanup_job();
 perform test_ok(30,'observed-empty becomes eligible again',new_job.status='leased');
 perform public.finish_animal_photo_cleanup_attempt(new_job.animal_id,new_job.lease_token,new_job.generation,'retry','timeout');
end $$;
reset role;
delete from public.animal_photo_cleanup_jobs where animal_id=test_id(11);
set role service_role;
select public.discover_animal_photo_cleanup_jobs();
select test_ok(29,'discovery reconstructs missing job',exists(select 1 from public.animal_photo_cleanup_jobs where animal_id=test_id(11)));
-- Ambiguous failures need three consecutive reports, not a single event.
update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()+interval '1 day' where status='pending';
do $$ declare j public.animal_photo_cleanup_jobs; i int; code text; begin
 foreach code in array array['internal_error','permission_denied','no_progress'] loop
  update public.animal_photo_cleanup_jobs set status='pending',next_attempt_at=clock_timestamp()-interval '1 second',uncertain_failure_count=0 where animal_id=test_id(10);
  for i in 1..3 loop
   select * into strict j from public.claim_animal_photo_cleanup_job();
   perform public.finish_animal_photo_cleanup_attempt(j.animal_id,j.lease_token,j.generation,'retry',code);
   select * into strict j from public.animal_photo_cleanup_jobs where animal_id=j.animal_id;
   if j.status<>(case when i=3 then 'quarantined' else 'pending' end) or j.uncertain_failure_count<>i then raise exception 'Wrong uncertainty policy'; end if;
   if i<3 then update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=j.animal_id; end if;
  end loop;
 end loop;
 perform test_ok(38,'all uncertain errors retry twice then quarantine',true);
 update public.animal_photo_cleanup_jobs set status='pending',next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=test_id(10);
 select * into strict j from public.claim_animal_photo_cleanup_job();
 perform public.finish_animal_photo_cleanup_attempt(j.animal_id,j.lease_token,j.generation,'retry','timeout');
 select * into strict j from public.animal_photo_cleanup_jobs where animal_id=j.animal_id;
 perform test_ok(39,'transient error resets uncertainty and retries',j.status='pending' and j.uncertain_failure_count=0);
end $$;
reset role;
-- Concurrency scripts run after this harness and register test 26.
select n,label from public.test_results order by n;
