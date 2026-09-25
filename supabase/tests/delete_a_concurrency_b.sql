-- OPTIONAL LOCAL ONLY; start while connection A displays "Locks held".
\set ON_ERROR_STOP on
DO $$ begin
 if current_database() <> 'mi_finca_delete_a_test' then raise exception 'LOCAL ONLY'; end if;
end $$;
begin;
set local statement_timeout='45s';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$ declare reply jsonb; started timestamptz := clock_timestamp(); begin
 reply := public.sync_soft_delete('animals','10000000-0000-4000-8000-000000000006',auth.uid(),'20000000-0000-4000-8000-000000000003');
 if clock_timestamp()-started < interval '1 second' then raise exception 'No overlap observed: repeat with fresh fixture and start B earlier'; end if;
 if reply->>'operation_id' <> '20000000-0000-4000-8000-000000000001' then raise exception 'Concurrent retry replaced first operation'; end if;
 if (select count(*) from public.sync_deletions where collection='animals' and entity_id='10000000-0000-4000-8000-000000000006') <> 1 then raise exception 'Duplicate ledger'; end if;
 begin
   insert into public.animals(id,user_id,name) values
    ('10000000-0000-4000-8000-000000000007',auth.uid(),'late after concurrent delete');
   raise exception using errcode='XX000',message='Concurrent terminal identity revived';
 exception when sqlstate 'P0001' then
   if sqlerrm <> 'SYNC_ENTITY_DELETED' then raise; end if;
 end;
end $$;
commit;
