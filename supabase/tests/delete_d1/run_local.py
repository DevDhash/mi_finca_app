"""Local disposable PostgreSQL only; no network/ports/remote credentials.
Concurrency uses psql pipe barriers and observed advisory waits, not SQL sleeps.
"""
from pathlib import Path
import subprocess
import time
import json
import uuid
import threading
from queue import Queue

ROOT = Path(__file__).resolve().parents[3]
NAME = 'delete-d1-' + uuid.uuid4().hex[:10]
DB = 'mi_finca_delete_a_test'
MIG = '/work/migrations/20260928000100_delete_d1_paddock_movement_contract.sql'
OWNER = '00000000-0000-4000-8000-000000000001'
OTHER = '00000000-0000-4000-8000-000000000002'
COUNT = 0


def uid(n):
    return f'20000000-0000-4000-8000-{n:012d}'


def command(*args):
    return subprocess.run(args, text=True, capture_output=True, check=True)


def base():
    return ['docker', 'exec', '-i', NAME, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', DB, '-v', 'ON_ERROR_STOP=1']


def sql(text, error=None):
    r = subprocess.run(base(), input=text, text=True, capture_output=True, timeout=30)
    if error:
        assert r.returncode and error in r.stderr, (error, r.stderr)
    else:
        assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def client(text):
    return f"set role authenticated; set request.jwt.claim.sub='{OWNER}';\n" + text


def ok(label, condition=True):
    global COUNT
    assert condition, label
    COUNT += 1
    print(f'PASS {COUNT}: {label}', flush=True)


def delete(n, collection='paddocks', owner=OWNER):
    return f"select public.sync_soft_delete('{collection}','{uid(n)}','{owner}','{uid(n+9000)}');"


def move(animal, src, dest, mid):
    source = 'NULL' if src is None else "'" + uid(src) + "'"
    return f"select public.sync_move_animal('{OWNER}','{uid(animal)}','{uid(mid)}',{source},'{uid(dest)}','2026-01-01T12:00:00Z',3);"


def paddock(n, owner=OWNER):
    sql(client(f"insert into public.paddocks(id,user_id,name) values('{uid(n)}','{owner}','fixture');") if owner == OWNER else
        f"insert into public.paddocks(id,user_id,name) values('{uid(n)}','{owner}','fixture');")


def animal(n, p):
    sql(client(f"insert into public.animals(id,user_id,paddock_id,name) values('{uid(n)}','{OWNER}','{uid(p)}','fixture');"))


def race(first, second, expected_error, label):
    a = subprocess.Popen(base(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    b = None
    try:
        a.stdin.write(client("set statement_timeout='15s'; begin;\n" + first + "\n\\echo BARRIER\n")); a.stdin.flush()
        # Readiness follows completion of the winning operation, not elapsed time.
        lines = Queue()
        def read_winner():
            for line in a.stdout:
                lines.put(line)
            lines.put('')
        threading.Thread(target=read_winner, daemon=True).start()
        deadline = time.monotonic() + 20
        while True:
            line = lines.get(timeout=max(0.01, deadline-time.monotonic()))
            assert line, a.stderr.read()
            if line.strip() == 'BARRIER':
                break
        b = subprocess.Popen(base(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        b.stdin.write(client("set statement_timeout='15s'; set application_name='d1_contender';\n" + second)); b.stdin.close()
        deadline = time.monotonic() + 10
        waiting = False
        while time.monotonic() < deadline:
            waiting = sql("select exists(select from pg_stat_activity where application_name='d1_contender' and wait_event='advisory');") == 't'
            if waiting or b.poll() is not None:
                break
        assert waiting, 'Contender did not wait on shared advisory gate'
        a.stdin.write('commit;\n\\q\n'); a.stdin.flush()
        assert a.wait(timeout=10) == 0, a.stderr.read()
        returncode = b.wait(timeout=10)
        assert returncode != 0 if expected_error else returncode == 0
        err = b.stderr.read()
        if expected_error:
            assert expected_error in err, err
        ok(label)
    finally:
        for p in (a, b):
            if p is not None and p.poll() is None:
                p.kill(); p.wait()


def corrected_tests():
    def literal(value):
        if value is None: return 'NULL'
        if isinstance(value, int): return str(value)
        return "'" + value.replace("'", "''") + "'"
    cases = json.loads((ROOT/'test/fixtures/d1_business_calendar.json').read_text())
    for zone in ('UTC','Asia/Tokyo','America/New_York'):
        for c in cases:
            expression = ','.join(literal(c[k]) for k in ('status','days','end','reference'))
            result = sql(f"set timezone='{zone}'; select public.d1_can_receive_animals({expression});")
            assert result == ('t' if c['expected'] else 'f'), (zone,c)
    ok('shared calendar cases independent of PostgreSQL timezone')
    for n in range(300, 307): paddock(n)
    animal(400,300)
    sql("update paddocks set status='Agotado' where id='"+uid(301)+"';")
    sql(client(move(400,300,301,500)), 'SYNC_PADDOCK_NOT_AVAILABLE')
    ok('RPC ineligible before any mutation or receipt', sql(f"select paddock_id='{uid(300)}' and not exists(select from sync_movement_operations where movement_id='{uid(500)}') from animals where id='{uid(400)}';")=='t')
    sql(client(f"insert into animal_movements(id,user_id,animal_id,from_paddock_id,to_paddock_id,moved_at) values('{uid(501)}','{OWNER}','{uid(400)}','{uid(300)}','{uid(302)}','2026-01-01T12:00:00Z');"))
    sql(client(move(400,300,302,501)), 'SYNC_MOVE_LEGACY_CONFLICT')
    ok('legacy collision neither succeeds nor completes partial move',sql(f"select paddock_id='{uid(300)}' from animals where id='{uid(400)}';")=='t')
    request = move(400,300,302,502)
    race(request,request,None,'concurrent identical RPC retries succeed once')
    ok('single history and single receipt',sql(f"select (select count(*) from animal_movements where id='{uid(502)}')=1 and (select count(*) from sync_movement_operations where movement_id='{uid(502)}')=1;")=='t')
    for altered in [request.replace(uid(400),uid(401)),request.replace(uid(300),uid(303)),request.replace(uid(302),uid(303)),request.replace('12:00:00','13:00:00'),request.replace(',3);',',4);'),request.replace(',3);',',NULL);')]:
        sql(client(altered),'SYNC_MOVE_ID_CONFLICT')
    sql(client(request).replace(OWNER,OTHER),'SYNC_NOT_AUTHORIZED')
    ok('receipt conflicts on every relevant field; other owner gets no data')
    for stmt in ['select * from sync_movement_operations;', 'update sync_movement_operations set planned_grazing_days=5;', 'delete from sync_movement_operations;', 'insert into sync_movement_operations(movement_id) values(gen_random_uuid());']:
        sql(client(stmt),'permission denied')
    ok('client cannot read or mutate receipts')
    animal(401,303)
    occupied = move(401,303,302,503).replace(',3);',',NULL);')
    sql(client(occupied)); sql(client(occupied.replace(',NULL);',',7);')))
    ok('occupied destination ignores unused plan canonically')
    # Direct movement alone does not create current occupancy: history never blocks delete.
    direct = f"insert into animal_movements(id,user_id,animal_id,from_paddock_id,to_paddock_id,moved_at) values('{uid(504)}','{OWNER}','{uid(400)}','{uid(302)}','{uid(304)}',now());"
    race(direct,delete(304),None,'direct movement first then empty paddock deletion preserves history')
    direct2=direct.replace(uid(504),uid(505)).replace(uid(304),uid(305))
    race(delete(305),direct2,'SYNC_ENTITY_DELETED','delete first blocks direct movement')
    paddock(307)
    animal(402,307)
    rejected = f"""do $$ begin
      perform public.sync_soft_delete('paddocks','{uid(307)}','{OWNER}','{uid(9307)}');
      raise exception 'DELETE_SHOULD_FAIL';
    exception when others then
      if sqlerrm <> 'SYNC_PADDOCK_OCCUPIED' then raise; end if;
    end $$;
    update paddocks set name=name where id='{uid(307)}';"""
    race(rejected,move(402,307,302,507),None,'source DELETE rejected first, later MOVE can leave source')
    # Late error AFTER receipt insertion still rolls back the complete transaction.
    sql("create function public.d1_fail_receipt() returns trigger language plpgsql as $$ begin raise exception 'RECEIPT_FAILURE'; end $$; create trigger fail_receipt after insert on sync_movement_operations for each row execute function public.d1_fail_receipt();")
    snapshot_sql="select jsonb_agg(to_jsonb(a) order by id) from animals a; select jsonb_agg(to_jsonb(p) order by id) from paddocks p; select jsonb_agg(to_jsonb(m) order by id) from animal_movements m; select jsonb_agg(to_jsonb(o) order by movement_id) from sync_movement_operations o;"
    before=sql(snapshot_sql)
    sql(client(move(400,302,306,506)), 'RECEIPT_FAILURE')
    ok('late failure restores animals/paddocks/history/receipts',before==sql(snapshot_sql))
    sql('drop trigger fail_receipt on sync_movement_operations; drop function public.d1_fail_receipt();')


def main():
    command('docker', 'run', '--detach', '--name', NAME, '--network', 'none',
            '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust',
            '-e', 'POSTGRES_DB='+DB, '--mount', f'type=bind,source={ROOT}/supabase,target=/work,readonly', 'postgres:17-alpine')
    try:
        deadline = time.monotonic()+20
        while time.monotonic() < deadline:
            r = subprocess.run(base()+['-c','select 1'], capture_output=True)
            if r.returncode == 0:
                break
        sql('\\i /work/tests/delete_a_local.sql')
        ok('existing DELETE A full local SQL suite before D1')
        sql('''
        alter table public.paddocks add column farm_id uuid, add column status text default 'Disponible',
          add column grazing_start_date timestamptz, add column last_grazing_end_date timestamptz,
          add column planned_grazing_days integer, add column required_rest_days integer;
        alter table public.animals add column farm_id uuid,
          add column paddock_id uuid references public.paddocks(id) on delete set null;
        alter table public.animal_movements add column animal_id uuid references public.animals(id) on delete cascade,
          add column from_paddock_id uuid references public.paddocks(id) on delete set null,
          add column to_paddock_id uuid references public.paddocks(id) on delete set null,
          add column moved_at timestamptz, add column created_at timestamptz default now();
        create function public.d1_fixture_timestamp() returns trigger language plpgsql as
          $$ begin new.updated_at=clock_timestamp(); return new; end $$;
        create trigger set_paddocks_updated_at before update on public.paddocks for each row execute function public.d1_fixture_timestamp();
        create trigger set_animals_updated_at before update on public.animals for each row execute function public.d1_fixture_timestamp();
        create trigger set_movements_updated_at before update on public.animal_movements for each row execute function public.d1_fixture_timestamp();
        ''')
        sql("alter table animal_movements add column unknown_required text not null default 'fixture'; alter table animal_movements alter column unknown_required drop default;")
        sql('\\i '+MIG, 'D1_UNKNOWN_REQUIRED_MOVEMENT_COLUMN')
        ok('unknown mandatory movement column rejects before install', sql("select to_regprocedure('public.d1_lock_domain()') is null;")=='t')
        sql('alter table animal_movements drop column unknown_required;')
        sql('\\i '+MIG)
        sql('\\i '+MIG, 'D1_ALREADY_INSTALLED')
        sql('\\i /work/rollback/delete_d1.sql')
        sql('\\i '+MIG)
        ok('empty receipt rollback and reinstall')
        ok('one-shot install; reinstall aborts')
        for n in range(10, 23): paddock(n)
        paddock(30, OTHER)
        animal(100, 10)
        sql(client(delete(10)), 'SYNC_PADDOCK_OCCUPIED')
        ok('occupied deletion leaves no ledger or deleted_at', sql(f"select (deleted_at is null and not exists(select from sync_deletions where entity_id='{uid(10)}')) from paddocks where id='{uid(10)}';") == 't')
        sql(client(f"update paddocks set deleted_at=now() where id='{uid(10)}';"),'SYNC_PADDOCK_OCCUPIED')
        ok('legacy direct occupied deletion rejected')
        sql(client(delete(11)))
        before = sql(f"select row_to_json(d) from sync_deletions d where entity_id='{uid(11)}'; select last_value from sync_deletions_sequence_seq;")
        sql(client(delete(11)))
        sql(client(delete(11).replace(uid(9011),uid(9999))))
        ok('retry preserves sequence/operation/time', before == sql(f"select row_to_json(d) from sync_deletions d where entity_id='{uid(11)}'; select last_value from sync_deletions_sequence_seq;"))
        sql(client(delete(30)), 'SYNC_NOT_AUTHORIZED')
        ok('cross-owner delete rejected')
        for expression in [move(100,10,11,200),f"update animals set paddock_id='{uid(11)}' where id='{uid(100)}';",
            f"insert into animal_movements(id,user_id,animal_id,to_paddock_id,moved_at) values('{uid(201)}','{OWNER}','{uid(100)}','{uid(11)}',now());",
            f"update paddocks set deleted_at=null where id='{uid(11)}';"]:
            sql(client(expression),'SYNC_ENTITY_DELETED')
        ok('terminal destination blocks move/direct assignment/insert/revival')
        sql(client(move(100,10,30,200)), 'SYNC_REFERENCE_NOT_AUTHORIZED')
        sql(client(f"update animals set paddock_id='{uid(30)}' where id='{uid(100)}';"),'SYNC_REFERENCE_NOT_AUTHORIZED')
        ok('cross-owner destination rejected in RPC and direct write')
        first = sql(client(move(100,10,12,200)))
        sql(client(move(100,12,13,202)))
        ok('normal moves atomic, nullable farm allowed',sql(f"select paddock_id='{uid(13)}' and farm_id is null from animals where id='{uid(100)}';")=='t')
        history = sql(f"select jsonb_agg(to_jsonb(m) order by id) from animal_movements m where animal_id='{uid(100)}';")
        sql(client(delete(12)))
        ok('A-B-C history immutable after B delete',history==sql(f"select jsonb_agg(to_jsonb(m) order by id) from animal_movements m where animal_id='{uid(100)}';"))
        ok('retry does not rewind later movement', first==sql(client(move(100,10,12,200))) and sql(f"select paddock_id='{uid(13)}' from animals where id='{uid(100)}';")=='t')
        sql(client(f"update animal_movements set name='history annotation' where id='{uid(200)}';"))
        sql(client(f"update animal_movements set moved_at=now() where id='{uid(200)}';"),'SYNC_ENTITY_DELETED')
        ok('unchanged historical references accepted; historical redirect rejected')
        sql(client(f"delete from paddocks where id='{uid(11)}';"))
        ok('authenticated hard delete remains blocked',sql(f"select count(*) from paddocks where id='{uid(11)}';")=='1')
        # Inject failure AFTER animal and movement writes to prove whole transaction rollback.
        sql("create function public.d1_test_fail() returns trigger language plpgsql as $$ begin raise exception 'INJECTED_FAILURE'; end $$; create trigger zz_d1_test_fail after update on paddocks for each row execute function public.d1_test_fail();")
        snapshot = sql(f"select to_jsonb(a) from animals a where id='{uid(100)}';")
        sql(client(move(100,13,14,203)), 'INJECTED_FAILURE')
        ok('late failure rolls back animal AND inserted movement', snapshot==sql(f"select to_jsonb(a) from animals a where id='{uid(100)}';") and sql(f"select count(*) from animal_movements where id='{uid(203)}';")=='0')
        sql('drop trigger zz_d1_test_fail on paddocks; drop function public.d1_test_fail();')
        for col in ('animals','expenses'):
            if col=='expenses': sql(client(f"insert into expenses(id,user_id,name) values('{uid(101)}','{OWNER}','fixture');"))
            sql(client(delete(100 if col=='animals' else 101,col)))
        ok('DELETE A animal and expense still work after D1')
        animal(110,15)
        race(move(110,15,16,210),delete(16),'SYNC_PADDOCK_OCCUPIED','MOVE-first blocks occupied destination DELETE')
        race(delete(17),move(110,16,17,211),'SYNC_ENTITY_DELETED','DELETE-first blocks MOVE')
        race(move(110,16,18,212),delete(16),None,'source exit-first permits source DELETE')
        sql(client(delete(18)), 'SYNC_PADDOCK_OCCUPIED')
        ok('source DELETE-first while occupied rejected')
        race(f"update animals set paddock_id='{uid(19)}' where id='{uid(110)}';",delete(19),'SYNC_PADDOCK_OCCUPIED','direct UPDATE coordinates with DELETE')
        race(delete(20),f"update animals set paddock_id='{uid(20)}' where id='{uid(110)}';",'SYNC_ENTITY_DELETED','DELETE coordinates with direct UPDATE')
        sql(client(delete(99)))
        sql(client(f"insert into paddocks(id,user_id,name) values('{uid(99)}','{OWNER}','late');"),'SYNC_ENTITY_DELETED')
        ok('absent identity remains terminal')
        ok('helper ACLs private and move authenticated-only', sql("select not has_function_privilege('anon','public.sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer)','EXECUTE') and has_function_privilege('authenticated','public.sync_move_animal(uuid,uuid,uuid,uuid,uuid,timestamptz,integer)','EXECUTE') and not has_function_privilege('authenticated','public.d1_assert_empty(uuid,uuid)','EXECUTE');")=='t')
        sql(client(move(110,19,21,210)), 'SYNC_MOVE_ID_CONFLICT')
        sql(client(move(110,15,21,230)), 'SYNC_MOVE_SOURCE_CONFLICT')
        ok('movement identity reuse and stale source rejected')
        sql(client(f"insert into animal_movements(id,user_id,animal_id,from_paddock_id,to_paddock_id,moved_at) values('{uid(240)}','{OWNER}','{uid(110)}','{uid(30)}','{uid(21)}',now());"),'SYNC_REFERENCE_NOT_AUTHORIZED')
        ok('direct movement cross-owner origin rejected')
        baseline = sql("select jsonb_agg(to_jsonb(d) order by sequence) from sync_deletions d; select jsonb_agg(to_jsonb(m) order by id) from animal_movements m; select jsonb_agg(to_jsonb(a) order by id) from animals a; select jsonb_agg(to_jsonb(p) order by id) from paddocks p;")
        sql('\\i /work/rollback/delete_d1.sql', 'D1_ROLLBACK_HAS_COMPLETED_OPERATIONS')
        ok('operational rollback blocked and preserves ledger and every domain row', baseline == sql("select jsonb_agg(to_jsonb(d) order by sequence) from sync_deletions d; select jsonb_agg(to_jsonb(m) order by id) from animal_movements m; select jsonb_agg(to_jsonb(a) order by id) from animals a; select jsonb_agg(to_jsonb(p) order by id) from paddocks p;"))
        corrected_tests()
        print(f'D1: {COUNT} scenario groups PASS')
    finally:
        command('docker','rm','--force',NAME)


if __name__ == '__main__':
    main()
