-- Additional D1 review only. SELECT-only; never invokes a business RPC.
-- No need to repeat Stage 1/2 data audits.
SELECT c.relname,a.attname,format_type(a.atttypid,a.atttypmod) AS data_type,
  a.attnotnull,pg_get_expr(d.adbin,d.adrelid) AS default_expression
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid
LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
WHERE n.nspname='public' AND NOT a.attisdropped AND
 ((c.relname='paddocks' AND a.attname IN
   ('status','required_rest_days','grazing_start_date','last_grazing_end_date','planned_grazing_days'))
 OR (c.relname='animal_movements' AND a.attname IN ('moved_at','created_at')))
ORDER BY c.relname,a.attname;

-- Expected zero rows: extra required columns not supplied by RPC.
SELECT a.attname,format_type(a.atttypid,a.atttypmod) AS data_type
FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
WHERE a.attrelid='public.animal_movements'::regclass AND a.attnum>0
 AND NOT a.attisdropped AND a.attnotnull AND d.oid IS NULL
 AND a.attidentity='' AND a.attgenerated=''
 AND a.attname NOT IN ('id','user_id','animal_id','from_paddock_id','to_paddock_id','moved_at','created_at');

-- Expected postgres installer, same RPC owner, definer and privileges true.
SELECT current_user,pg_get_userbyid(p.proowner) AS rpc_owner,p.prosecdef,
 has_schema_privilege(current_user,'public','CREATE') AS can_create,
 (SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname=current_user) AS bypass_rls
FROM pg_proc p WHERE p.oid=to_regprocedure('public.sync_soft_delete(text,uuid,uuid,uuid)');
SELECT c.oid::regclass AS relation,pg_get_userbyid(c.relowner) AS owner,
 has_table_privilege(current_user,c.oid,'TRIGGER') AS can_create_trigger,
 has_table_privilege(current_user,c.oid,'UPDATE') AS can_lock_relation
FROM pg_class c WHERE c.oid IN ('public.paddocks'::regclass,'public.animals'::regclass,
 'public.animal_movements'::regclass,'public.sync_deletions'::regclass);

-- Inspect additional inherited defaults; migration explicitly revokes client access.
SELECT pg_get_userbyid(defaclrole) AS owner,
 CASE WHEN defaclnamespace=0 THEN '(global)' ELSE defaclnamespace::regnamespace::text END AS scope,
 defaclobjtype,defaclacl
FROM pg_default_acl WHERE defaclrole=(SELECT oid FROM pg_roles WHERE rolname=current_user)
 AND defaclnamespace IN (0,'public'::regnamespace) AND defaclobjtype IN ('f','r');

-- Expected NULL table and zero function/trigger rows before first installation.
SELECT to_regclass('public.sync_movement_operations') AS receipt_table;
SELECT p.oid::regprocedure AS collision FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace AND p.proname IN
 ('d1_lock_domain','d1_lock_statement','d1_assert_empty','d1_assert_paddock',
  'd1_guard_references','d1_can_receive_animals','sync_move_animal');
SELECT tgrelid::regclass AS relation,tgname FROM pg_trigger
WHERE tgrelid IN ('public.paddocks'::regclass,'public.animals'::regclass,'public.animal_movements'::regclass)
 AND tgname IN ('d1_domain_gate','d1_reference_guard');

-- Expected one row. Explicit conversions must return Sept 12 then Sept 13.
SELECT name FROM pg_timezone_names WHERE name='America/Lima';
SELECT ('2026-09-13T04:59:59Z'::timestamptz AT TIME ZONE 'America/Lima')::date AS before_boundary,
 ('2026-09-13T05:00:00Z'::timestamptz AT TIME ZONE 'America/Lima')::date AS at_boundary;
