"""Local contract checks; PostgreSQL integration is in run_local.py."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / 'supabase/migrations/20260926000100_cleanup_automation_security_hardening.sql'
DOC = ROOT / 'supabase/DELETE_E2E_SECURITY_HARDENING.md'


def manifest(sql):
    return json.loads(sql.split('$manifest$')[1])


def rollback():
    return DOC.read_text().split('```sql\n', 1)[1].split('```', 1)[0]


class Contract(unittest.TestCase):
    def setUp(self):
        self.sql = MIGRATION.read_text()
        self.targets = manifest(self.sql)

    def test_exact_functions(self):
        expected = {
            'net._await_response(bigint)',
            'net._encode_url_with_params_array(text,text[])',
            'net._http_collect_response(bigint,boolean)',
            'net._urlencode_string(character varying)',
            'net.check_worker_is_up()',
            'net.http_collect_response(bigint,boolean)',
            'net.http_delete(text,jsonb,jsonb,integer,jsonb)',
            'net.http_get(text,jsonb,jsonb,integer)',
            'net.http_post(text,jsonb,jsonb,jsonb,integer)',
            'net.wait_until_running()', 'net.wake()', 'net.worker_restart()',
        }
        self.assertEqual(expected, {t['name'] for t in self.targets
                                   if t['kind'] == 'function' and t['name'].startswith('net.')})
        self.assertEqual(22, len(self.targets))

    def test_vault_schema_baseline_is_unchanged(self):
        vault = next(t for t in self.targets if t['name'] == 'vault')
        expected = '{supabase_admin=UC/supabase_admin,postgres=U*/supabase_admin,service_role=U/supabase_admin}'
        self.assertEqual(expected, vault['before'])
        self.assertEqual(expected, vault['after'])

    def test_no_unapproved_operations(self):
        executable = re.sub(r'--[^\n]*', '', self.sql)
        self.assertNotRegex(executable, r'(?i)\bCASCADE\b|\bALTER\b|\bINSERT\s+INTO\b|\bDELETE\s+FROM\b')
        self.assertNotRegex(executable, r'(?is)GRANT\b[^;]*\bTO\s+service_role')
        self.assertNotRegex(executable, r'(?i)SELECT\s+(?:net\.http_|cron\.schedule)')
        self.assertNotIn('sb_secret_', self.sql)
        self.assertNotIn('https://', self.sql)

    def test_only_whole_states(self):
        self.assertIn('phase=0 AND NOT (all_before OR all_after)', self.sql)
        self.assertIn('phase=1 AND NOT all_after', self.sql)
        self.assertLess(self.sql.index('HARDENING_UNKNOWN_OR_PARTIAL_ACL_STATE'),
                        self.sql.index('      GRANT SELECT'))
        self.assertIn('pg_catalog.aclexplode', self.sql)
        self.assertIn('is_grantable', self.sql)
        self.assertIn('attacl IS NOT NULL', self.sql)

    def test_rollback_exact_inverse(self):
        reverse = manifest(rollback())
        self.assertEqual(len(self.targets), len(reverse))
        for original, restored in zip(self.targets, reverse):
            self.assertEqual(original['name'], restored['name'])
            self.assertEqual(original['before'], restored['after'])
            self.assertEqual(original['after'], restored['before'])
        self.assertIn('NO ejecutar rollback', DOC.read_text())

    def test_transactions(self):
        for sql in [self.sql, rollback()]:
            self.assertIn('BEGIN;\nDO $hardening$', sql)
            self.assertTrue(sql.rstrip().endswith('COMMIT;'))
            self.assertIn("current_user <> 'supabase_admin'", sql)
            self.assertIn('HARDENING_VAULT_EXPOSURE', sql)


if __name__ == '__main__':
    unittest.main()
