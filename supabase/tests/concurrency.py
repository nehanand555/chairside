"""Race real PostgreSQL connections; no third-party Python dependencies needed."""
from concurrent.futures import ThreadPoolExecutor
import json
import subprocess
from threading import Barrier
from uuid import uuid4


def sql(statement, check=True):
    result = subprocess.run(["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", statement], capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result


owners, customers, businesses, resources, services = ([str(uuid4()) for _ in range(2)] for _ in range(5))
for i, user in enumerate(owners + customers):
    sql(f"insert into auth.users(id,phone,phone_confirmed_at) values('{user}','+6421999000{i}',now()); insert into public.profiles(id,display_name) values('{user}','Race test');")
for i in range(2):
    sql(f"""
      insert into public.businesses(id,owner_id,name,kind,status,suburb,public_lat,public_lng,publish_consent)
      values('{businesses[i]}','{owners[i]}','Concurrent shop','barber','approved','Auckland',-36.85,174.76,true);
      insert into public.resources(id,business_id,name) values('{resources[i]}','{businesses[i]}','Chair');
      insert into public.services(id,business_id,name,minutes,price_cents) values('{services[i]}','{businesses[i]}','Haircut',30,3500);
      insert into public.hours select '{businesses[i]}',d,'00:00'::time,'23:59'::time from generate_series(1,7) d;
    """)


def race(calls):
    barrier = Barrier(2)

    def book(args):
        user, index = args
        claims = json.dumps({"sub": user, "aal": "aal1"})
        barrier.wait()
        return sql(f"""begin; set local role authenticated;
          select set_config('request.jwt.claims','{claims}',true);
          select public.create_visit('{businesses[index]}','{services[index]}','{resources[index]}','appointment',
            (((now() at time zone 'Pacific/Auckland')::date+1)+time '10:00') at time zone 'Pacific/Auckland');
          commit;""", check=False)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(book, calls))
    assert sorted(r.returncode == 0 for r in results) == [False, True], [r.stderr for r in results]
    failed = next(r for r in results if r.returncode)
    assert any(fragment in failed.stderr for fragment in ("no longer available", "just taken", "active visit")), failed.stderr


race([(customers[0], 0), (customers[1], 0)])
assert sql(f"select count(*) from public.visits where business_id='{businesses[0]}' and status='booked'").stdout.strip() == "1"
print("PASS: two customers racing for one slot produce exactly one booking")
sql("update public.visits set status='cancelled' where status='booked'")
race([(customers[0], 0), (customers[0], 1)])
assert sql(f"select count(*) from public.visits where customer_id='{customers[0]}' and status='booked'").stdout.strip() == "1"
print("PASS: one customer racing at different businesses gets only one active visit")
