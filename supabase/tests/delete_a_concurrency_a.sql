-- OPTIONAL LOCAL ONLY, after delete_a_local.sql, in connection A.
-- Not executed by the agent. Use a new fixture run for each attempt.
\set ON_ERROR_STOP on
DO $$ begin
 if current_database() <> 'mi_finca_delete_a_test' then raise exception 'LOCAL ONLY'; end if;
end $$;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000006',auth.uid(),'20000000-0000-4000-8000-000000000001');
select public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000007',auth.uid(),'20000000-0000-4000-8000-000000000002');
\echo Locks held: start delete_a_concurrency_b.sql NOW in a second local connection.
select pg_sleep(30);
commit;
