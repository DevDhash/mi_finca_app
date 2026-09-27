-- DELETE E / E2E: ACL-only hardening. No remote invocation or credential.
-- Run with current_user = supabase_admin. Unknown/partial states abort.
BEGIN;
DO $hardening$
DECLARE
  targets constant jsonb := $manifest$
[
  {
    "kind": "schema",
    "name": "net",
    "before": "{supabase_admin=UC/supabase_admin,=U/supabase_admin,supabase_functions_admin=U/supabase_admin,postgres=U/supabase_admin,anon=U/supabase_admin,authenticated=U/supabase_admin,service_role=U/supabase_admin}",
    "after": "{supabase_admin=UC/supabase_admin,supabase_functions_admin=U/supabase_admin,postgres=U/supabase_admin,service_role=U/supabase_admin}",
    "rls": null
  },
  {
    "kind": "schema",
    "name": "cron",
    "before": "{supabase_admin=UC/supabase_admin,postgres=U*/supabase_admin}",
    "after": "{supabase_admin=UC/supabase_admin,postgres=U*/supabase_admin}",
    "rls": null
  },
  {
    "kind": "schema",
    "name": "vault",
    "before": "{supabase_admin=UC/supabase_admin,postgres=U*/supabase_admin,service_role=U/supabase_admin}",
    "after": "{supabase_admin=UC/supabase_admin,postgres=U*/supabase_admin,service_role=U/supabase_admin}",
    "rls": null
  },
  {
    "kind": "table",
    "name": "net.http_request_queue",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,=arwdDxtm/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,postgres=ard/supabase_admin,supabase_functions_admin=arwdDxtm/supabase_admin}",
    "rls": false
  },
  {
    "kind": "table",
    "name": "net._http_response",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,=arwdDxtm/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,postgres=ard/supabase_admin,supabase_functions_admin=arwdDxtm/supabase_admin}",
    "rls": false
  },
  {
    "kind": "sequence",
    "name": "net.http_request_queue_id_seq",
    "before": "{supabase_admin=rwU/supabase_admin,=rwU/supabase_admin}",
    "after": "{supabase_admin=rwU/supabase_admin,postgres=U/supabase_admin,supabase_functions_admin=rwU/supabase_admin}",
    "rls": null
  },
  {
    "kind": "table",
    "name": "cron.job",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,=r/supabase_admin,postgres=r*/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,postgres=r*/supabase_admin}",
    "rls": true
  },
  {
    "kind": "table",
    "name": "cron.job_run_details",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,=rd/supabase_admin,postgres=a*r*w*d*D*x*m*/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,postgres=a*r*w*d*D*x*m*/supabase_admin}",
    "rls": true
  },
  {
    "kind": "function",
    "name": "net._await_response(bigint)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._encode_url_with_params_array(text,text[])",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._http_collect_response(bigint,boolean)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._urlencode_string(character varying)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.check_worker_is_up()",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_collect_response(bigint,boolean)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_delete(text,jsonb,jsonb,integer,jsonb)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_get(text,jsonb,jsonb,integer)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_post(text,jsonb,jsonb,jsonb,integer)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.wait_until_running()",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.wake()",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.worker_restart()",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "cron.schedule(text,text)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin,postgres=X*/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X*/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "cron.schedule(text,text,text)",
    "before": "{supabase_admin=X/supabase_admin,=X/supabase_admin,postgres=X*/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,postgres=X*/supabase_admin}",
    "rls": null
  }
]
$manifest$::jsonb;
  t jsonb;
  object_oid oid;
  actual_owner oid;
  actual_acl aclitem[];
  actual_rls boolean;
  actual_kind "char";
  actual_normal jsonb;
  before_normal jsonb;
  after_normal jsonb;
  all_before boolean;
  all_after boolean;
  phase integer;
  client text;
  privilege text;
BEGIN
  IF current_user <> 'supabase_admin' THEN
    RAISE EXCEPTION 'HARDENING_REQUIRES_SUPABASE_ADMIN';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_extension WHERE extname='pg_net' AND extversion='0.20.4' AND extnamespace='public'::regnamespace)
     OR NOT EXISTS (SELECT FROM pg_catalog.pg_extension WHERE extname='pg_cron' AND extversion='1.6.4' AND extnamespace='pg_catalog'::regnamespace) THEN
    RAISE EXCEPTION 'HARDENING_EXTENSION_VERSION_MISMATCH';
  END IF;
  IF pg_catalog.current_setting('pg_net.username', true) IS DISTINCT FROM 'postgres'
     OR NOT EXISTS (SELECT FROM pg_catalog.pg_stat_activity
       WHERE usename='postgres' AND backend_type='pg_net 0.20.4 worker'
         AND application_name='pg_net 0.20.4') THEN
    RAISE EXCEPTION 'HARDENING_WORKER_MISMATCH';
  END IF;
  IF EXISTS (SELECT FROM pg_catalog.pg_auth_members
      WHERE member IN ('anon'::regrole, 'authenticated'::regrole))
     OR EXISTS (SELECT FROM pg_catalog.pg_roles
      WHERE rolname IN ('anon','authenticated') AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'HARDENING_CLIENT_ROLE_MISMATCH';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='supabase_admin' AND rolsuper)
     OR NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='postgres' AND NOT rolsuper AND rolbypassrls) THEN
    RAISE EXCEPTION 'HARDENING_ADMIN_ROLE_MISMATCH';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='net') <> 12
     OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='cron' AND p.proname='schedule') <> 2 THEN
    RAISE EXCEPTION 'HARDENING_FUNCTION_SET_MISMATCH';
  END IF;
  -- Phase zero validates EVERY object before any GRANT/REVOKE.
  -- Phase one proves the complete final ACL, including grantors/options.
  FOR phase IN 0..1 LOOP
    all_before := true;
    all_after := true;
    FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets) LOOP
      object_oid := NULL;
      actual_owner := NULL;
      actual_acl := NULL;
      IF t->>'kind' = 'schema' THEN
        SELECT oid,nspowner,nspacl INTO object_oid,actual_owner,actual_acl
          FROM pg_catalog.pg_namespace WHERE nspname=t->>'name';
      ELSIF t->>'kind' = 'function' THEN
        object_oid := pg_catalog.to_regprocedure(t->>'name');
        SELECT proowner,coalesce(proacl,pg_catalog.acldefault('f',proowner)),prokind
          INTO actual_owner,actual_acl,actual_kind FROM pg_catalog.pg_proc WHERE oid=object_oid;
        IF actual_kind IS DISTINCT FROM 'f' THEN
          RAISE EXCEPTION 'HARDENING_FUNCTION_KIND_MISMATCH: %',t->>'name';
        END IF;
      ELSE
        object_oid := pg_catalog.to_regclass(t->>'name');
        SELECT relowner,relacl,relrowsecurity,relkind
          INTO actual_owner,actual_acl,actual_rls,actual_kind
          FROM pg_catalog.pg_class WHERE oid=object_oid;
        IF actual_kind IS DISTINCT FROM
           (CASE WHEN t->>'kind'='sequence' THEN 'S' ELSE 'r' END)::"char"
           OR (t->>'kind'='table' AND actual_rls IS DISTINCT FROM (t->>'rls')::boolean)
           OR EXISTS (SELECT FROM pg_catalog.pg_attribute
              WHERE attrelid=object_oid AND attacl IS NOT NULL) THEN
          RAISE EXCEPTION 'HARDENING_RELATION_MISMATCH: %',t->>'name';
        END IF;
      END IF;
      IF object_oid IS NULL OR actual_owner IS DISTINCT FROM 'supabase_admin'::regrole::oid THEN
        RAISE EXCEPTION 'HARDENING_OWNER_OR_OBJECT_MISMATCH: %',t->>'name';
      END IF;
      SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY grantor,grantee,privilege_type,is_grantable),'[]'::jsonb)
        INTO actual_normal FROM pg_catalog.aclexplode(actual_acl) x;
      SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY grantor,grantee,privilege_type,is_grantable),'[]'::jsonb)
        INTO before_normal FROM pg_catalog.aclexplode((t->>'before')::aclitem[]) x;
      SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY grantor,grantee,privilege_type,is_grantable),'[]'::jsonb)
        INTO after_normal FROM pg_catalog.aclexplode((t->>'after')::aclitem[]) x;
      all_before := all_before AND actual_normal=before_normal;
      all_after := all_after AND actual_normal=after_normal;
    END LOOP;
    IF phase=0 AND NOT (all_before OR all_after) THEN
      RAISE EXCEPTION 'HARDENING_UNKNOWN_OR_PARTIAL_ACL_STATE';
    END IF;
    IF phase=1 AND NOT all_after THEN
      RAISE EXCEPTION 'HARDENING_FINAL_ACL_MISMATCH';
    END IF;
    -- Check isolation before mutations as well as after them.
    FOREACH client IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF pg_catalog.has_schema_privilege(client,'vault','USAGE')
         OR pg_catalog.has_any_column_privilege(client,'vault.secrets','SELECT')
         OR pg_catalog.has_any_column_privilege(client,'vault.decrypted_secrets','SELECT') THEN
        RAISE EXCEPTION 'HARDENING_VAULT_EXPOSURE';
      END IF;
    END LOOP;
    IF phase=0 AND all_before THEN
      GRANT SELECT,INSERT,DELETE ON net.http_request_queue,net._http_response TO postgres;
      GRANT USAGE ON SEQUENCE net.http_request_queue_id_seq TO postgres;
      GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN
        ON net.http_request_queue,net._http_response TO supabase_functions_admin;
      GRANT SELECT,UPDATE,USAGE ON SEQUENCE net.http_request_queue_id_seq TO supabase_functions_admin;
      FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets)
        WHERE value->>'kind'='function' AND value->>'name' LIKE 'net.%' LOOP
        EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO postgres, supabase_functions_admin',t->>'name');
      END LOOP;
      -- All preservation grants precede all revocations.
      REVOKE USAGE ON SCHEMA net FROM PUBLIC,anon,authenticated;
      REVOKE SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN
        ON net.http_request_queue,net._http_response FROM PUBLIC,anon,authenticated;
      REVOKE SELECT,UPDATE,USAGE ON SEQUENCE net.http_request_queue_id_seq FROM PUBLIC,anon,authenticated;
      REVOKE SELECT ON cron.job FROM PUBLIC,anon,authenticated;
      REVOKE SELECT,DELETE ON cron.job_run_details FROM PUBLIC,anon,authenticated;
      FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets) WHERE value->>'kind'='function' LOOP
        EXECUTE pg_catalog.format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',t->>'name');
      END LOOP;
    END IF;
  END LOOP;
  FOREACH client IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF pg_catalog.has_schema_privilege(client,'net','USAGE')
       OR pg_catalog.has_schema_privilege(client,'cron','USAGE') THEN
      RAISE EXCEPTION 'HARDENING_CLIENT_SCHEMA_ACCESS';
    END IF;
    FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets) LOOP
      IF t->>'kind'='table' THEN
        FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
          IF pg_catalog.has_table_privilege(client,t->>'name',privilege) THEN
            RAISE EXCEPTION 'HARDENING_CLIENT_TABLE_ACCESS';
          END IF;
        END LOOP;
      ELSIF t->>'kind'='function' AND pg_catalog.has_function_privilege(client,t->>'name','EXECUTE') THEN
        RAISE EXCEPTION 'HARDENING_CLIENT_FUNCTION_ACCESS';
      ELSIF t->>'kind'='sequence' AND pg_catalog.has_sequence_privilege(client,t->>'name','SELECT,UPDATE,USAGE') THEN
        RAISE EXCEPTION 'HARDENING_CLIENT_SEQUENCE_ACCESS';
      END IF;
    END LOOP;
  END LOOP;
  IF NOT pg_catalog.has_schema_privilege('postgres','net','USAGE')
     OR NOT pg_catalog.has_sequence_privilege('postgres','net.http_request_queue_id_seq','USAGE') THEN
    RAISE EXCEPTION 'HARDENING_POSTGRES_ACCESS_LOST';
  END IF;
  FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets)
    WHERE value->>'name' LIKE 'net.%' LOOP
    IF t->>'kind'='table' THEN
      FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','DELETE'] LOOP
        IF NOT pg_catalog.has_table_privilege('postgres',t->>'name',privilege) THEN
          RAISE EXCEPTION 'HARDENING_WORKER_ACCESS_LOST';
        END IF;
      END LOOP;
    ELSIF t->>'kind'='function' AND NOT pg_catalog.has_function_privilege('postgres',t->>'name','EXECUTE') THEN
      RAISE EXCEPTION 'HARDENING_POSTGRES_FUNCTION_ACCESS_LOST';
    END IF;
  END LOOP;
  -- The complete final ACL comparison also proves preservation of
  -- supabase_admin ownership/grants and supabase_functions_admin grants.
  -- No new service_role grant is present in the final manifest.
END;
$hardening$;
COMMIT;
