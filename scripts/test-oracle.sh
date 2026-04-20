#!/usr/bin/env bash
# test-oracle.sh
#
# Quick smoke test that Oracle Instant Client + python-oracledb can reach
# the DB defined in the current dbt profile / Airflow connection env vars.
#
# Reads from env:
#   ORACLE_HOST, ORACLE_PORT, ORACLE_SERVICE, ORACLE_USER, ORACLE_PASSWORD
set -euo pipefail

python - <<'PY'
import os, sys
import oracledb

host = os.environ.get("ORACLE_HOST")
port = int(os.environ.get("ORACLE_PORT", "1521"))
service = os.environ.get("ORACLE_SERVICE")
user = os.environ.get("ORACLE_USER")
password = os.environ.get("ORACLE_PASSWORD")

missing = [k for k in ("ORACLE_HOST","ORACLE_SERVICE","ORACLE_USER","ORACLE_PASSWORD")
           if not os.environ.get(k)]
if missing:
    sys.exit(f"Missing required env vars: {', '.join(missing)}")

dsn = oracledb.makedsn(host, port, service_name=service)
print(f"Connecting to {user}@{dsn} ...")

with oracledb.connect(user=user, password=password, dsn=dsn) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT sysdate, user FROM dual")
        sysdate, db_user = cur.fetchone()
        print(f"OK. sysdate={sysdate}, connected_user={db_user}")
PY
