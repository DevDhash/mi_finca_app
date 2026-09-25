\set ON_ERROR_STOP on
begin;
set local role service_role;
select public.test_ok(26,'concurrent second claim skips locked job',not exists(select 1 from public.claim_animal_photo_cleanup_job()));
commit;
