"""Real PostgreSQL 17 ACL tests in an isolated disposable container.

Does NOT certify Supabase extensions/worker: the exact environment guard is
replaced ONLY in the in-memory test input because plain PostgreSQL lacks pg_net.
The unmodified migration is separately tested to fail before changes.
No ports, credentials, network calls, existing containers or volumes are used.
"""
import subprocess
import uuid
from test_contract import MIGRATION, manifest, rollback

IMAGE = 'postgres:17-alpine'
NAME = 'cleanup-acl-test-' + uuid.uuid4().hex[:12]
SQL = MIGRATION.read_text()
TARGETS = manifest(SQL)


def docker(*args, **kwargs):
    return subprocess.run(['docker', *args], check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def psql(sql, success=True):
    result = subprocess.run(
        ['docker', 'exec', '-i', NAME, 'psql', '-X', '-qAt',
         '-h', '127.0.0.1', '-v', 'ON_ERROR_STOP=1', '-U', 'fixture_admin', '-d', 'postgres'],
        input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if success and result.returncode:
        raise AssertionError(result.stderr)
    if not success and not result.returncode:
        raise AssertionError('Expected SQL failure')
    return result


def acl_sql(t, field='before'):
    return f"""
DO $$ DECLARE a record; BEGIN
  FOR a IN SELECT * FROM aclexplode('{t[field]}'::aclitem[]) LOOP
    EXECUTE format('GRANT %s ON {t['kind']} {t['name']} TO %s%s',
      a.privilege_type,
      CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
      CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
END $$;
"""


def fixture():
    parts = ['''
CREATE ROLE supabase_admin SUPERUSER;
CREATE ROLE postgres BYPASSRLS;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role BYPASSRLS;
CREATE ROLE supabase_functions_admin;
SET ROLE supabase_admin;
CREATE SCHEMA net;
CREATE SCHEMA cron;
CREATE SCHEMA vault;
CREATE TABLE vault.secrets (secret text);
CREATE VIEW vault.decrypted_secrets AS SELECT secret FROM vault.secrets;
CREATE TABLE net.http_request_queue (id bigint, headers jsonb);
CREATE TABLE net._http_response (id bigint, content text);
CREATE SEQUENCE net.http_request_queue_id_seq;
CREATE TABLE cron.job (id bigint);
CREATE TABLE cron.job_run_details (id bigint);
ALTER TABLE cron.job ENABLE ROW LEVEL SECURITY;
ALTER TABLE cron.job_run_details ENABLE ROW LEVEL SECURITY;
''']
    for t in TARGETS:
        if t['kind'] == 'function':
            parts.append(f"CREATE FUNCTION {t['name']} RETURNS void LANGUAGE sql AS 'SELECT';")
        else:
            parts.append(f"REVOKE ALL ON {t['kind']} {t['name']} FROM PUBLIC;")
            parts.append(acl_sql(t))
    # cron functions have explicit grant options in baseline; net funcs default NULL.
    for t in TARGETS:
        if t['kind'] == 'function' and t['name'].startswith('cron.'):
            parts.append(acl_sql(t))
    psql('\n'.join(parts))


def environment_fixture(sql):
    start = sql.index('  IF NOT EXISTS (SELECT FROM pg_catalog.pg_extension')
    end = sql.index('  IF EXISTS (SELECT FROM pg_catalog.pg_auth_members', start)
    return sql[:start] + '  -- TEST ONLY: extension/worker guard unavailable in fixture.\n' + sql[end:]


def snapshot():
    # Effective normalized ACLs including owner/grantor/options; no relation data.
    return psql('''SELECT jsonb_agg(x ORDER BY x::text) FROM (
      SELECT jsonb_build_array('r',n.nspname,c.relname,c.relowner,c.relrowsecurity,(SELECT jsonb_agg(to_jsonb(a) ORDER BY grantor,grantee,privilege_type,is_grantable) FROM aclexplode(c.relacl) a)) x
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('net','cron')
      UNION ALL
      SELECT jsonb_build_array('n',nspname,nspowner,(SELECT jsonb_agg(to_jsonb(a) ORDER BY grantor,grantee,privilege_type,is_grantable) FROM aclexplode(nspacl) a)) FROM pg_namespace
        WHERE nspname IN ('net','cron','vault')
      UNION ALL
      SELECT jsonb_build_array('f',p.oid::regprocedure::text,p.proowner,
          (SELECT jsonb_agg(to_jsonb(a) ORDER BY grantor,grantee,privilege_type,is_grantable)
           FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a))
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('net','cron')
    ) s;''').stdout.strip()


def apply(sql=SQL, success=True):
    return psql('SET ROLE supabase_admin;\n' + environment_fixture(sql), success)


def main():
    docker('run', '--detach', '--name', NAME, '--network', 'none',
           '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_USER=fixture_admin',
           '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', IMAGE)
    try:
        docker('exec', NAME, 'sh', '-c',
               'until pg_isready -h 127.0.0.1 -U fixture_admin -d postgres >/dev/null; do sleep 0.2; done')
        fixture()
        before = snapshot()
        failed = psql('SET ROLE supabase_admin;\n' + SQL, False)
        assert 'HARDENING_EXTENSION_VERSION_MISMATCH' in failed.stderr
        assert snapshot() == before
        print('PASS unmodified migration rejects missing real extensions atomically')
        failed = psql('SET ROLE postgres;\n' + SQL, False)
        assert 'HARDENING_REQUIRES_SUPABASE_ADMIN' in failed.stderr
        assert snapshot() == before
        print('PASS ordinary postgres runner rejected before any changes')
        # Independently test guard failures on actual PostgreSQL catalog state.
        cases = [
            ("REVOKE GRANT OPTION FOR USAGE ON SCHEMA vault FROM postgres;",
             "GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;",
             'HARDENING_UNKNOWN_OR_PARTIAL_ACL_STATE'),
            ("GRANT service_role TO anon;", "REVOKE service_role FROM anon;",
             'HARDENING_CLIENT_ROLE_MISMATCH'),
            ("ALTER TABLE net._http_response OWNER TO postgres;",
             "ALTER TABLE net._http_response OWNER TO supabase_admin;",
             'HARDENING_OWNER_OR_OBJECT_MISMATCH'),
            ("ALTER TABLE net._http_response ENABLE ROW LEVEL SECURITY;",
             "ALTER TABLE net._http_response DISABLE ROW LEVEL SECURITY;",
             'HARDENING_RELATION_MISMATCH'),
            ("CREATE FUNCTION net.unreviewed() RETURNS void LANGUAGE sql AS 'SELECT';",
             "DROP FUNCTION net.unreviewed();", 'HARDENING_FUNCTION_SET_MISMATCH'),
            ("GRANT SELECT ON vault.secrets TO anon;",
             "REVOKE SELECT ON vault.secrets FROM anon;", 'HARDENING_VAULT_EXPOSURE'),
        ]
        for change, undo, error in cases:
            psql('SET ROLE supabase_admin; ' + change)
            changed = snapshot()
            assert error in apply(success=False).stderr
            assert snapshot() == changed
            psql('SET ROLE supabase_admin; ' + undo)
        print('PASS membership, owner, RLS, unexpected function and Vault exposure guards')
        apply()
        final = snapshot()
        apply()
        assert snapshot() == final
        print('PASS real PostgreSQL baseline -> final -> idempotent final')
        # Deliberate mixed state must fail before changing anything else.
        psql('SET ROLE supabase_admin; GRANT SELECT ON net._http_response TO PUBLIC;')
        mixed = snapshot()
        assert 'HARDENING_UNKNOWN_OR_PARTIAL_ACL_STATE' in apply(success=False).stderr
        assert snapshot() == mixed
        psql('SET ROLE supabase_admin; REVOKE SELECT ON net._http_response FROM PUBLIC;')
        print('PASS partial ACL state rejected atomically')
        # Column ACL must fail closed even when relation ACLs match.
        psql('SET ROLE supabase_admin; GRANT SELECT(headers) ON net.http_request_queue TO anon;')
        unexpected = snapshot()
        assert 'HARDENING_RELATION_MISMATCH' in apply(success=False).stderr
        assert snapshot() == unexpected
        psql('SET ROLE supabase_admin; REVOKE SELECT(headers) ON net.http_request_queue FROM anon;')
        # Empty attacl is still an unexpected ACL by design: restore fixture via rollback
        # after dropping this unused fixture column (test container only).
        psql('SET ROLE supabase_admin; ALTER TABLE net.http_request_queue DROP COLUMN headers;')
        print('PASS column ACL rejected')
        apply(rollback())
        assert snapshot() == before
        apply(rollback())
        assert snapshot() == before
        print('PASS exact effective ACL rollback and idempotent baseline')
        # Force a late assertion after all grants: transaction must undo all changes.
        altered = environment_fixture(SQL).replace(
            "  -- The complete final ACL comparison", "  RAISE EXCEPTION 'TEST_LATE_FAILURE';\n  -- The complete final ACL comparison")
        failed = psql('SET ROLE supabase_admin;\n' + altered, False)
        assert 'TEST_LATE_FAILURE' in failed.stderr
        assert snapshot() == before
        print('PASS late exception rolls back every grant/revoke')
    finally:
        docker('rm', '--force', NAME)


if __name__ == '__main__':
    main()
