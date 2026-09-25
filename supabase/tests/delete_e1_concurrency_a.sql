-- Invoked only by run_delete_e1_local.sh against its isolated fixture container.
\set ON_ERROR_STOP on
begin;
set local role service_role;
set local application_name='e1_claim_a';
do $$ begin
 if (select count(*) from public.claim_animal_photo_cleanup_job())<>1 then raise exception 'First claim must win'; end if;
end $$;
select pg_sleep(8); -- Runner waits until this barrier is visible in pg_stat_activity.
commit;
