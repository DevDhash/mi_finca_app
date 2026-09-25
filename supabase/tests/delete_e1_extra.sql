-- After delete_e1_local.sql, in the same disposable fixture only.
\set ON_ERROR_STOP on
do $$ begin if current_database()<>'mi_finca_delete_e1_test' then raise exception 'LOCAL_FIXTURE_ONLY'; end if; end $$;
set role authenticated;
select set_config('request.jwt.claim.sub',test_id(1)::text,false);
select set_config('request.jwt.claim.role','authenticated',false);
do $$ declare ext text; q text; begin
 foreach ext in array array['jpg','jpeg','png','heic','webp','avif','JPG','a1'] loop
  if not public.animal_photo_insert_allowed(replace(test_path(1,22),'.jpg','.'||ext)) then raise exception 'Extension rejected %',ext; end if;
 end loop;
 perform test_ok(44,'extensions match Flutter alphanumeric contract',true);
 foreach q in array array['select public.discover_animal_photo_cleanup_jobs()',
 'select * from public.claim_animal_photo_cleanup_job()',
 'select public.finish_animal_photo_cleanup_attempt(null,null,null,''observed_empty'')'] loop
  begin execute q; raise exception 'Client invoked server RPC'; exception when insufficient_privilege then null; end;
 end loop;
 perform test_ok(45,'authenticated cannot invoke server RPCs',true);
end $$;
reset role;
set role service_role;
do $$ declare j public.animal_photo_cleanup_jobs; i int; begin
 begin perform public.discover_animal_photo_cleanup_jobs(0); raise exception 'Invalid limit';
 exception when sqlstate '22023' then null; end;
 begin perform public.discover_animal_photo_cleanup_jobs(null); raise exception 'NULL limit';
 exception when sqlstate '22023' then null; end;
 perform test_ok(46,'invalid discovery limits fail closed',true);
 begin update public.animal_photo_cleanup_jobs set user_id=test_id(2) where animal_id=test_id(10); raise exception 'Owner mutation accepted';
 exception when check_violation then if sqlerrm<>'PHOTO_CLEANUP_IDENTITY_IMMUTABLE' then raise; end if; end;
 perform test_ok(47,'job owner immutable',true);
 update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()+interval '1 day' where status='pending';
 update public.animal_photo_cleanup_jobs set status='pending',lease_token=null,lease_expires_at=null,next_verification_at=null,
 next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=test_id(10);
 select * into strict j from public.claim_animal_photo_cleanup_job();
 begin perform public.finish_animal_photo_cleanup_attempt(j.animal_id,j.lease_token,j.generation,'quarantined','internal_error'); raise exception 'Immediate internal quarantine';
 exception when sqlstate '22023' then null; end;
 perform test_ok(48,'uncertain error cannot request immediate quarantine',true);
 perform public.finish_animal_photo_cleanup_attempt(j.animal_id,j.lease_token,j.generation,'retry','internal_error');
 update public.animal_photo_cleanup_jobs set next_attempt_at=clock_timestamp()-interval '1 second' where animal_id=j.animal_id;
 select * into strict j from public.claim_animal_photo_cleanup_job();
 perform public.finish_animal_photo_cleanup_attempt(j.animal_id,j.lease_token,j.generation,'observed_empty');
 perform test_ok(49,'successful verification resets uncertainty',
  (select uncertain_failure_count=0 and status='observed_empty' and next_verification_at>verified_empty_at
   from public.animal_photo_cleanup_jobs where animal_id=j.animal_id));
end $$;
reset role;
begin isolation level repeatable read;
set local role service_role;
do $$ begin
 begin perform public.claim_animal_photo_cleanup_job(); raise exception 'Unsupported isolation';
 exception when sqlstate '0A000' then null; end;
end $$;
rollback;
select test_ok(50,'fixed snapshot isolation rejected',true);
