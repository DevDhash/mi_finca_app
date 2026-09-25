-- LOCAL HARNESS ONLY. Production rollback needs separate approval/review.
\set ON_ERROR_STOP on
begin;
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'mi_finca_delete_e1_test' then raise exception 'LOCAL_FIXTURE_ONLY'; end if;
end $$;
lock table public.animal_photo_cleanup_jobs in access exclusive mode;
do $$ begin
 if exists(select 1 from public.animal_photo_cleanup_jobs where status<>'pending'
   or attempt_count<>0 or generation<>0 or uncertain_failure_count<>0
   or lease_token is not null or lease_expires_at is not null or last_attempt_at is not null
   or last_error_code is not null or verified_empty_at is not null or next_verification_at is not null) then
  raise exception 'E1_ROLLBACK_REQUIRES_PRESERVING_OPERATIONAL_JOBS';
 end if;
end $$;
alter policy animal_photos_insert_guard on storage.objects with check(
 bucket_id<>'animal-photos' or (auth.role()='authenticated' and (storage.foldername(name))[1]=(select auth.uid())::text));
drop function public.finish_animal_photo_cleanup_attempt(uuid,uuid,bigint,text,text);
drop function public.claim_animal_photo_cleanup_job();
drop function public.discover_animal_photo_cleanup_jobs(integer);
drop trigger animal_photo_cleanup_job_guard on public.animal_photo_cleanup_jobs;
drop function public.animal_photo_cleanup_job_guard();
drop table public.animal_photo_cleanup_jobs;
drop function public.animal_photo_insert_allowed(text);
commit;
