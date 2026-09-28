-- DELETE D1: operator-run READ ONLY preflight. Not a migration.
-- Run in project fgzaddfcbiriocpbwreb. No RPC/function invocation, no secrets.
-- Stage 1: catalogs only. Review columns before running Stage 2 separately.
SELECT current_user, session_user, current_database(),
       current_setting('transaction_isolation') AS isolation;

SELECT c.oid::regclass AS relation, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity, c.relforcerowsecurity,
       a.attnum, a.attname, format_type(a.atttypid,a.atttypmod) AS type,
       a.attnotnull, a.attidentity, a.attgenerated,
       pg_get_expr(d.adbin,d.adrelid) AS default_expression
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
WHERE n.nspname='public'
  AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions')
ORDER BY relation::text,a.attnum;

-- Includes inbound FKs, not only constraints declared on these four tables.
SELECT conrelid::regclass AS relation, conname, contype, convalidated,
       condeferrable, condeferred, pg_get_constraintdef(oid,true) AS definition
FROM pg_constraint
WHERE conrelid IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions'))
   OR confrelid IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions'))
ORDER BY relation::text,conname;

SELECT t.tgrelid::regclass AS relation, t.tgname, t.tgenabled, t.tgisinternal,
       pg_get_triggerdef(t.oid,true) AS definition,
       p.oid::regprocedure AS function_signature, pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef, p.provolatile, p.proconfig
FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
WHERE t.tgrelid IN (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions'))
ORDER BY relation::text,t.tgname;

-- Inventory candidate RPCs and custom trigger functions, without executing any.
SELECT p.oid::regprocedure AS signature, pg_get_userbyid(p.proowner) AS owner,
       pg_get_function_result(p.oid) AS result, p.prosecdef, p.provolatile,
       p.proconfig, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND (p.proname ~ '(sync_|paddock|movement|move_animal)'
  OR p.oid IN (SELECT t.tgfoid FROM pg_trigger t
    WHERE NOT t.tgisinternal AND t.tgrelid IN (
      SELECT c.oid FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions'))))
ORDER BY signature::text;

-- Narrow known DELETE A definitions only. Do not export unknown functions
-- containing embedded credentials; review those privately before sharing.
SELECT p.oid::regprocedure AS signature, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('sync_soft_delete','sync_guard_entity');

SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname='public'
AND tablename IN ('paddocks','animals','animal_movements','sync_deletions')
ORDER BY tablename,policyname;

SELECT c.oid::regclass AS relation, i.indexrelid::regclass AS index,
       i.indisvalid,i.indisready,pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions')
ORDER BY relation::text,index::text;

SELECT c.oid::regclass AS relation, acl.grantor::regrole AS grantor,
       CASE WHEN acl.grantee=0 THEN 'PUBLIC' ELSE acl.grantee::regrole::text END AS grantee,
       acl.privilege_type,acl.is_grantable
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
WHERE n.nspname='public' AND c.relname IN ('paddocks','animals','animal_movements','sync_deletions')
ORDER BY relation::text,grantee,privilege_type;

-- Stage 2: run ONLY after Stage 1 confirms these columns/types exist.
-- Aggregate counts only: no names, photos, payloads or credentials.
SELECT count(*) AS live_animals_with_missing_foreign_or_terminal_paddock
FROM public.animals a LEFT JOIN public.paddocks p ON p.id=a.paddock_id
WHERE a.deleted_at IS NULL AND a.paddock_id IS NOT NULL
  AND (p.id IS NULL OR p.user_id IS DISTINCT FROM a.user_id OR p.deleted_at IS NOT NULL);

SELECT count(*) AS movements_with_missing_or_foreign_references
FROM public.animal_movements m
LEFT JOIN public.animals a ON a.id=m.animal_id
LEFT JOIN public.paddocks f ON f.id=m.from_paddock_id
LEFT JOIN public.paddocks t ON t.id=m.to_paddock_id
WHERE a.id IS NULL OR a.user_id IS DISTINCT FROM m.user_id
   OR (m.from_paddock_id IS NOT NULL AND (f.id IS NULL OR f.user_id IS DISTINCT FROM m.user_id))
   OR (m.to_paddock_id IS NOT NULL AND (t.id IS NULL OR t.user_id IS DISTINCT FROM m.user_id));

SELECT count(*) AS paddock_terminal_mismatches
FROM public.paddocks p FULL JOIN
  (SELECT * FROM public.sync_deletions WHERE collection='paddocks') d ON d.entity_id=p.id
WHERE (p.deleted_at IS NOT NULL AND (d.entity_id IS NULL
  OR d.user_id IS DISTINCT FROM p.user_id OR d.deleted_at IS DISTINCT FROM p.deleted_at))
  OR (d.entity_id IS NOT NULL AND p.id IS NOT NULL AND p.deleted_at IS NULL);

-- Missing domain rows with tombstones are intentionally valid DELETE A identities.
-- farm_id NULL counts without requiring the column to exist on every table.
SELECT 'paddocks' AS relation,count(*) AS total,
       count(*) FILTER (WHERE to_jsonb(p)->>'farm_id' IS NULL) AS farm_id_null_or_absent
FROM public.paddocks p
UNION ALL SELECT 'animals',count(*),count(*) FILTER (WHERE to_jsonb(a)->>'farm_id' IS NULL)
FROM public.animals a
UNION ALL SELECT 'animal_movements',count(*),count(*) FILTER (WHERE to_jsonb(m)->>'farm_id' IS NULL)
FROM public.animal_movements m;
