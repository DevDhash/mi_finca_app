# DELETE E2E — Security hardening

> **SUSPENDIDO / NO APLICADO — NO APLICAR AUTOMÁTICAMENTE.**
>
> `20260926000100_cleanup_automation_security_hardening.sql` permanece en
> `supabase/migrations` para conservar el trabajo. NO ejecutar un `db push`
> indiscriminado: esta migración debe quedar excluida mientras esté suspendida.
> No se ha autorizado cambiar owners, memberships ni debilitar su guard.

**DELETE E: cleanup funcional validado; automatic wakeup pendiente.**

El cleanup, observed_empty, reverificación e idempotencia fueron validados por
el operador. Según el último estado confirmado, no existe scheduler desplegado
para este worker. Esta preservación local no realiza una nueva inspección remota
ni crea scheduler, credenciales o recursos. La automatización queda pendiente;
el hardening se conserva sin aplicar y separado de DELETE D.

LOCAL REVIEW ONLY. No migration has been applied remotely by this work.

Migration: `20260926000100_cleanup_automation_security_hardening.sql`. Requires
current_user=supabase_admin. postgres is not an authorized ACL grantor for these
objects despite BYPASSRLS. Do not change role memberships to bypass this.

## Contract

The embedded manifest fixes 22 objects: three schemas, four tables, one
sequence, 12 net functions and two cron.schedule overloads. ACL comparison uses
aclexplode including grantor, grantee, privilege and grant option. Entire
original or entire final state only; mixed states fail before grants.
Already-final reruns are no-ops. Function NULL ACL is normalized with
acldefault. No catalog writes, owner/RLS changes, configuration changes,
credentials, scheduler or network invocation.

postgres receives SELECT/INSERT/DELETE on both net tables, sequence USAGE, and
EXECUTE on the twelve net functions. Existing schema USAGE is preserved.
supabase_functions_admin receives only the effective permissions it already had
through PUBLIC on these objects (materialized explicitly). supabase_admin
remains owner/superuser. No new service_role grants. cron schemas/sequences stay
unchanged; cron.job and job_run_details lose public read/delete permissions as
applicable.

Column ACLs on target relations must be absent. Client memberships are
disallowed (the absence of direct memberships proves absence of transitive
memberships). Vault client isolation is checked before and after, but Vault ACLs
are not changed. Unlisted net functions/cron.schedule overloads cause failure.
Other cron functions are outside this change; clients have no cron schema
access.

Updates of extensions can reintroduce grants: rerun the audit after upgrades.
Concurrent administrative ACL changes must be excluded during
deployment/rollback.

## Rollback

**NO ejecutar rollback después de provisionar la credencial mientras pueda haber
requests con secretos en la cola.** Restore PUBLIC access only when safe. This
script neither drains the queue nor deletes secrets and must not be used to do
so. The script validates the entire hardened or restored state and rejects
drift. It restores effective ACLs and grant options exactly. Function proacl may
be an explicit default-equivalent ACL instead of its original NULL
representation. Never update pg_catalog to restore that representational detail.

```sql
-- Exact ACL rollback. Only before credential provisioning / secret-bearing requests.
-- Run with current_user = supabase_admin. Unknown/partial states abort.
BEGIN;
DO $hardening$
DECLARE
  targets constant jsonb := $manifest$
[
  {
    "kind": "schema",
    "name": "net",
    "before": "{supabase_admin=UC/supabase_admin,supabase_functions_admin=U/supabase_admin,postgres=U/supabase_admin,service_role=U/supabase_admin}",
    "after": "{supabase_admin=UC/supabase_admin,=U/supabase_admin,supabase_functions_admin=U/supabase_admin,postgres=U/supabase_admin,anon=U/supabase_admin,authenticated=U/supabase_admin,service_role=U/supabase_admin}",
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
    "before": "{supabase_admin=arwdDxtm/supabase_admin,postgres=ard/supabase_admin,supabase_functions_admin=arwdDxtm/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,=arwdDxtm/supabase_admin}",
    "rls": false
  },
  {
    "kind": "table",
    "name": "net._http_response",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,postgres=ard/supabase_admin,supabase_functions_admin=arwdDxtm/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,=arwdDxtm/supabase_admin}",
    "rls": false
  },
  {
    "kind": "sequence",
    "name": "net.http_request_queue_id_seq",
    "before": "{supabase_admin=rwU/supabase_admin,postgres=U/supabase_admin,supabase_functions_admin=rwU/supabase_admin}",
    "after": "{supabase_admin=rwU/supabase_admin,=rwU/supabase_admin}",
    "rls": null
  },
  {
    "kind": "table",
    "name": "cron.job",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,postgres=r*/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,=r/supabase_admin,postgres=r*/supabase_admin}",
    "rls": true
  },
  {
    "kind": "table",
    "name": "cron.job_run_details",
    "before": "{supabase_admin=arwdDxtm/supabase_admin,postgres=a*r*w*d*D*x*m*/supabase_admin}",
    "after": "{supabase_admin=arwdDxtm/supabase_admin,=rd/supabase_admin,postgres=a*r*w*d*D*x*m*/supabase_admin}",
    "rls": true
  },
  {
    "kind": "function",
    "name": "net._await_response(bigint)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._encode_url_with_params_array(text,text[])",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._http_collect_response(bigint,boolean)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net._urlencode_string(character varying)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.check_worker_is_up()",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_collect_response(bigint,boolean)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_delete(text,jsonb,jsonb,integer,jsonb)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_get(text,jsonb,jsonb,integer)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.http_post(text,jsonb,jsonb,jsonb,integer)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.wait_until_running()",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.wake()",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "net.worker_restart()",
    "before": "{supabase_admin=X/supabase_admin,postgres=X/supabase_admin,supabase_functions_admin=X/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "cron.schedule(text,text)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X*/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin,postgres=X*/supabase_admin}",
    "rls": null
  },
  {
    "kind": "function",
    "name": "cron.schedule(text,text,text)",
    "before": "{supabase_admin=X/supabase_admin,postgres=X*/supabase_admin}",
    "after": "{supabase_admin=X/supabase_admin,=X/supabase_admin,postgres=X*/supabase_admin}",
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
      GRANT USAGE ON SCHEMA net TO PUBLIC,anon,authenticated;
      GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN
        ON net.http_request_queue,net._http_response TO PUBLIC;
      GRANT SELECT,UPDATE,USAGE ON SEQUENCE net.http_request_queue_id_seq TO PUBLIC;
      GRANT SELECT ON cron.job TO PUBLIC;
      GRANT SELECT,DELETE ON cron.job_run_details TO PUBLIC;
      FOR t IN SELECT value FROM pg_catalog.jsonb_array_elements(targets) WHERE value->>'kind'='function' LOOP
        EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC',t->>'name');
        IF t->>'name' LIKE 'net.%' THEN
          EXECUTE pg_catalog.format('REVOKE EXECUTE ON FUNCTION %s FROM postgres, supabase_functions_admin',t->>'name');
        END IF;
      END LOOP;
      REVOKE SELECT,INSERT,DELETE ON net.http_request_queue,net._http_response FROM postgres;
      REVOKE USAGE ON SEQUENCE net.http_request_queue_id_seq FROM postgres;
      REVOKE SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN
        ON net.http_request_queue,net._http_response FROM supabase_functions_admin;
      REVOKE SELECT,UPDATE,USAGE ON SEQUENCE net.http_request_queue_id_seq FROM supabase_functions_admin;
    END IF;
  END LOOP;
  -- Complete normalized ACL comparison above proves original baseline restoration.
END;
$hardening$;
COMMIT;
```

## Post-hardening verification

The migration itself asserts the complete final ACL and effective client/worker
permissions in the same transaction. A thrown exception aborts every
grant/revoke. For inspection without reading data:

```sql
SELECT r.rolname,n.nspname,
  has_schema_privilege(r.oid,n.oid,'USAGE') AS usage
FROM pg_roles r CROSS JOIN pg_namespace n
WHERE r.rolname IN ('anon','authenticated')
  AND n.nspname IN ('net','cron','vault');

SELECT r.rolname,p.oid::regprocedure,
  has_function_privilege(r.oid,p.oid,'EXECUTE') AS execute
FROM pg_roles r CROSS JOIN pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE r.rolname IN ('anon','authenticated','postgres')
  AND (n.nspname='net' OR (n.nspname='cron' AND p.proname='schedule'));

SELECT r.rolname,t.name,
  has_any_column_privilege(r.oid,t.name,'SELECT') AS read_any_column
FROM pg_roles r CROSS JOIN (VALUES
 ('net.http_request_queue'),('net._http_response'),
 ('cron.job'),('cron.job_run_details'),
 ('vault.secrets'),('vault.decrypted_secrets')) t(name)
WHERE r.rolname IN ('anon','authenticated');
```

## Authorized later: harmless transport test

Not part of this migration. Requires separate authorization; run as postgres. No
credentials. Do not substitute the cleanup endpoint.

```sql
SELECT net.http_post(
  url := 'https://httpbin.org/post', body := NULL::jsonb,
  params := '{}'::jsonb,
  headers := '{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds := 110000
) AS request_id;
```

In a subsequent transaction, using the returned ID:

```sql
SELECT id,status_code,timed_out,error_msg,
  content::jsonb->>'data' = '' AS received_empty_body,
  content::jsonb->'headers'->>'Content-Length' AS received_content_length
FROM net._http_response WHERE id = <returned_request_id>;
```

Expected 200 / false / NULL / true / "0". This tests real enqueue/processing,
not a 110-second duration guarantee. No cleanup call is needed.

## Sequence

Review migration/tests → authorize administrative apply → assertions + harmless
transport → Vault provisioning → private wake function → explicitly authorized
private invocation → cron → Flutter E2E. MAX_JOBS=1 and DISCOVERY_LIMIT=1
unchanged.

## Local validation and limits

Commands:

```sh
python3 -m unittest discover -s supabase/tests/security_hardening -p 'test_*.py'
python3 supabase/tests/security_hardening/run_local.py
bash supabase/tests/run_delete_e1_local.sh
deno fmt --check supabase/functions/animal-photo-cleanup/
deno lint supabase/functions/animal-photo-cleanup/
deno check $(rg --files supabase/functions/animal-photo-cleanup -g '*.ts')
deno test supabase/functions/animal-photo-cleanup/tests/
node --test supabase/functions/animal-photo-cleanup/tests/*_test.ts
```

The ACL harness uses an existing PostgreSQL 17 image, no network, no published
ports, and disposable tmpfs data. It removes its container on exit. It executes
real GRANT/REVOKE and catalog checks, including normalized rollback comparisons.
It rejects wrong owner, RLS, membership, unexpected functions, column grants,
Vault exposure, mixed states, and proves rollback on a late exception.

**This is not a full Supabase extension/worker integration test.** Plain
PostgreSQL has no pg_net background worker. The harness tests that the
unmodified migration rejects missing extensions, then explicitly removes only
the extension/worker environment guard from its in-memory test input for ACL
tests. Repository SQL is never rewritten by the harness. Network functions are
inert fixture functions. A separately authorized post-hardening transport test
remains necessary.

Local results: 5 contract tests; 7 PostgreSQL scenario groups (including five
independent metadata rejection cases); E1 SQL 57 checks; Deno 358 tests; Node
358 tests. All passed. Deno formatting/lint/typecheck passed for 29 TypeScript
files. Flutter was not changed; its unrelated expense failures were not
modified.

## Final review — remote execution is BLOCKED

The ACL roundtrip is validated locally, but no supported hosted runner with
current_user=supabase_admin has been established. Do not run db push or weaken
the guard. Hosted SQL Editor does not normally provide the internal superuser;
CLI password authentication uses postgres, and passwordless CLI may provision a
cli_login_postgres login role. Neither is proof of current_user=supabase_admin.

Official references:

- https://supabase.com/docs/guides/self-hosting/remove-superuser-access
- https://supabase.com/docs/guides/troubleshooting/permission-denied-when-deleting-the-cli_login_postgres-role-808bae

Required next procedure (read-only first, not executed here):

1. In the actual intended runner, execute the identity query below.
2. If current_user is not supabase_admin, stop. Ask Supabase support for an
   authorized owner-level execution path for this exact ACL-only migration. Do
   not retrieve internal credentials or grant membership in supabase_admin.
3. Inventory client-callable SECURITY DEFINER functions. Repository migrations
   contain no queue-reading definer wrapper, but that does not certify the full
   hosted catalog. Review candidate definitions privately without exporting any
   embedded credentials. Include dynamic SQL and indirect calls; text searches
   alone are not proof of absence.
4. Only after those gates and explicit application approval, the authorized
   administrative operator runs the complete migration as one script, preserving
   its BEGIN/COMMIT and stopping on errors. Do not paste individual GRANTs.
5. Run postchecks below and separately authorize the credential-free httpbin
   test. Reconcile migration history through the agreed deployment process; do
   not blindly rerun other pending migrations or claim a Dashboard run records
   it.

```sql
SELECT current_user, session_user, current_database(),
       current_setting('role', true) AS selected_role;

-- Metadata only: no function bodies, environment, headers or secrets.
SELECT p.oid::regprocedure AS function_signature,
       pg_get_userbyid(p.proowner) AS owner,
       r.rolname AS callable_by,
       has_schema_privilege(r.oid,n.oid,'USAGE') AS schema_usage
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
CROSS JOIN pg_roles r
WHERE p.prosecdef
  AND r.rolname IN ('anon','authenticated')
  AND has_function_privilege(r.oid,p.oid,'EXECUTE')
  AND n.nspname NOT IN ('pg_catalog','information_schema')
ORDER BY function_signature::text, callable_by;
```

Postchecks: the first query must return zero rows, including PUBLIC. It
enumerates schema/table/column/sequence/function ACL entries instead of treating
PUBLIC as a login role. The migration's full manifest comparison additionally
checks retained administrative grants and grant options.

```sql
WITH privileges AS (
  SELECT 'schema:'||n.nspname AS object_name,a.*
  FROM pg_namespace n
  CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
  WHERE n.nspname IN ('net','cron','vault')
  UNION ALL
  SELECT 'relation:'||n.nspname||'.'||c.relname,a.*
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,
    acldefault(CASE WHEN c.relkind='S' THEN 's' ELSE 'r' END::"char",c.relowner))) a
  WHERE (n.nspname,c.relname) IN (
    ('net','http_request_queue'),('net','_http_response'),
    ('net','http_request_queue_id_seq'),('cron','job'),('cron','job_run_details'))
  UNION ALL
  SELECT 'column:'||n.nspname||'.'||c.relname||'.'||at.attname,a.*
  FROM pg_attribute at JOIN pg_class c ON c.oid=at.attrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(at.attacl) a
  WHERE (n.nspname,c.relname) IN (
    ('net','http_request_queue'),('net','_http_response'),
    ('cron','job'),('cron','job_run_details'))
  UNION ALL
  SELECT 'function:'||p.oid::regprocedure::text,a.*
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE n.nspname='net' OR (n.nspname='cron' AND p.proname='schedule')
)
SELECT * FROM privileges
WHERE grantee=0 OR grantee IN ('anon'::regrole,'authenticated'::regrole);

-- All rows must be true; evaluates each privilege separately (comma lists
-- in has_table_privilege would mean ANY privilege, not ALL).
SELECT r.role_name,t.object_name,p.privilege,
       has_table_privilege(r.role_name,t.object_name,p.privilege) AS allowed
FROM (VALUES ('postgres'),('supabase_functions_admin')) r(role_name)
CROSS JOIN (VALUES ('net.http_request_queue'),('net._http_response')) t(object_name)
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('DELETE')) p(privilege);

SELECT has_schema_privilege('postgres','net','USAGE') AS schema_usage,
       has_sequence_privilege('postgres','net.http_request_queue_id_seq','USAGE') AS sequence_usage;

SELECT p.oid::regprocedure,
       has_function_privilege('postgres',p.oid,'EXECUTE') AS postgres_execute,
       has_function_privilege('supabase_functions_admin',p.oid,'EXECUTE') AS functions_admin_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='net';
```

Review correction: added the unchanged Vault schema ACL to both manifests (22
objects). A regression case now rejects loss of postgres's Vault grant option
before any changes. The guard remains strict; a separate test proves postgres
cannot execute the migration. Local review rerun: 6 contract tests and 8
PostgreSQL scenario groups passed. The latter still do not certify hosted
extension runtime or a usable remote administrator identity.
