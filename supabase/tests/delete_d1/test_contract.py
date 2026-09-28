"""Static contract checks supplement, never substitute, PostgreSQL scenarios."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SQL = (ROOT / 'supabase/migrations/20260928000100_delete_d1_paddock_movement_contract.sql').read_text()
ROLLBACK = (ROOT / 'supabase/rollback/delete_d1.sql').read_text()
DELETE_A = (ROOT / 'supabase/migrations/20260924000200_delete_a_infrastructure.sql').read_text()


class Contract(unittest.TestCase):
    def test_no_unrelated_resources_or_domain_delete(self):
        stripped = re.sub(r'--[^\n]*', '', SQL).lower()
        for pattern in (r'\bdelete\s+from\b',
                        r'\b(?:storage|vault|net|cron)\.', r'\bfarm_id\b'):
            self.assertNotRegex(stripped, pattern)

    def test_rollback_exact_delete_a_rpc(self):
        start = DELETE_A.index('create or replace function public.sync_soft_delete(')
        end = DELETE_A.index('-- Backfill previously deleted identities;')
        self.assertIn(DELETE_A[start:end], ROLLBACK)
        for name in re.findall(r'create function public\.(\w+)\(', SQL):
            self.assertIn('drop function public.' + name + '(', ROLLBACK)
        self.assertNotIn('cascade', ROLLBACK.lower())
        self.assertIn('D1_ROLLBACK_HAS_COMPLETED_OPERATIONS', ROLLBACK)
        self.assertIn('enable row level security', SQL)

    def test_shared_gate_and_preledger_occupancy(self):
        self.assertEqual(SQL.count('create trigger d1_domain_gate before insert or update'), 3)
        rpc = SQL[SQL.index('create or replace function public.sync_soft_delete('):]
        self.assertLess(rpc.index('perform public.d1_lock_domain()'), rpc.index('pg_advisory_xact_lock'))
        self.assertLess(rpc.index('perform public.d1_assert_empty'), rpc.index('insert into public.sync_deletions'))
        self.assertNotIn('pg_sleep', SQL)

    def test_receipt_and_calendar(self):
        self.assertIn("at time zone 'America/Lima'", SQL)
        self.assertIn('SYNC_MOVE_LEGACY_CONFLICT', SQL)
        self.assertIn('receipt.planned_grazing_days is distinct from', SQL)
        self.assertIn('revoke all on public.sync_movement_operations from public,anon,authenticated,service_role;', SQL)
        self.assertLess(SQL.index('insert into public.animal_movements(id,user_id'),
                        SQL.index('insert into public.sync_movement_operations(movement_id'))

    def test_safe_function_search_path(self):
        self.assertEqual(len(re.findall(r'create (?:or replace )?function', SQL)),
                         SQL.count("security definer set search_path = ''"))


if __name__ == '__main__':
    unittest.main()
