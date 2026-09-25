-- Read-only verification AFTER manual migration. Safe for Supabase SQL Editor.
select to_regclass('public.sync_deletions') as ledger;
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema='public' and table_name='sync_deletions'
order by ordinal_position;
select tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname='public' and
 (tablename='sync_deletions' or policyname='sync_no_hard_delete')
order by tablename, policyname;
select c.relname, c.relrowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in
 ('sync_deletions','farms','paddocks','animals','animal_movements','expenses');
select c.relname, t.tgname, pg_get_triggerdef(t.oid)
from pg_trigger t join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and t.tgname='sync_terminal_identity';
select p.proname, p.prosecdef, p.proconfig, pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('sync_guard_entity','sync_soft_delete');
select has_table_privilege('authenticated','public.sync_deletions','SELECT') as own_select,
       has_table_privilege('anon','public.sync_deletions','SELECT') as anon_select,
       has_table_privilege('authenticated','public.sync_deletions','INSERT') as client_insert,
       has_table_privilege('authenticated','public.sync_deletions','UPDATE') as client_update,
       has_table_privilege('authenticated','public.sync_deletions','DELETE') as client_delete,
       has_function_privilege('authenticated','public.sync_soft_delete(text,uuid,uuid,uuid)','EXECUTE') as rpc_allowed,
       has_function_privilege('anon','public.sync_soft_delete(text,uuid,uuid,uuid)','EXECUTE') as rpc_anon;
-- Expected: true, false, false, false, false, true, false.
