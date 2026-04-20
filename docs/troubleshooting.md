# Troubleshooting

## Airflow UI shows a blank page or redirects to `/login` at the wrong URL

**Cause**: `AIRFLOW__WEBSERVER__BASE_URL` doesn't match the ODH proxy path.

**Fix**: Confirm the pod has `NB_PREFIX` set correctly — the entrypoint uses
it to derive BASE_URL. If `NB_PREFIX` is missing (some older ODH versions
don't inject it), add it explicitly to the Notebook CR:

```yaml
env:
  - name: NB_PREFIX
    value: /notebook/<your-namespace>/<your-workbench-name>
```

Then restart the workbench from the dashboard.

## `sqlite3.OperationalError: database is locked`

**Cause**: Two Airflow processes (scheduler + webserver) competed for the
SQLite file and one got stuck. Usually happens after a pod crash mid-write.

**Fix**: Run the reset script. It stops lingering processes and wipes the
metadata DB. DAG source files are untouched.

```bash
/opt/scripts/reset-airflow.sh
```

Re-log in to the Airflow UI afterwards; you'll need the new password at
`~/airflow/.admin_password`.

## DAGs don't appear in the UI

**Check in order:**

1. File is in the right place:
   ```bash
   ls ~/dags/
   echo $AIRFLOW__CORE__DAGS_FOLDER
   ```
2. No import errors:
   ```bash
   airflow dags list-import-errors
   ```
3. Scheduler is actually running:
   ```bash
   pgrep -af "airflow scheduler" || echo "scheduler not running"
   ```
4. If the scheduler is dead, restart Airflow:
   ```bash
   kill "$(cat ~/airflow/standalone.pid)" 2>/dev/null
   nohup airflow standalone > ~/logs/airflow-standalone.log 2>&1 &
   ```

## `dbt debug` fails with `ORA-12154: TNS:could not resolve`

**Cause**: Either the Oracle Secret isn't mounted, or the service name is
wrong.

**Fix**:
```bash
# Are the env vars present?
env | grep ^ORACLE_

# Is profiles.yml rendered?
cat ~/.dbt/profiles.yml

# Direct connectivity test (bypasses dbt)
bash /opt/scripts/test-oracle.sh
```

If `test-oracle.sh` succeeds but `dbt debug` still fails, check
`~/.dbt/profiles.yml` for unexpanded variables (e.g. literal `${ORACLE_HOST}`).
That means the entrypoint couldn't find one of the env vars when it ran.
Restart the pod after fixing the Secret.

## `ModuleNotFoundError` for a provider or dbt adapter

**Don't** `pip install` additional Airflow providers without the constraints
file — it silently breaks transitive deps. Instead:

```bash
CONSTRAINT="https://nexus.bbh.com/repository/airflow-constraints/constraints-3.1.7/constraints-3.11.txt"
pip install --user --constraint "$CONSTRAINT" apache-airflow-providers-<name>
```

For dbt adapters, just pip install normally — they don't share the Airflow
constraints.

If a package is missing from Nexus, file a ticket with the platform team to
mirror it. Do not point pip at public PyPI.

## Oracle Instant Client errors (`libclntsh.so: cannot open shared object`)

The image sets `LD_LIBRARY_PATH=/opt/oracle/instantclient` globally, but
something in your shell may have overridden it. Check:

```bash
echo $LD_LIBRARY_PATH
ldconfig -p | grep clntsh
```

If the library isn't found, fall back to python-oracledb's **thin** mode:

```python
import oracledb
oracledb.init_oracle_client = lambda: None   # force thin mode
```

dbt-oracle defaults to thin mode anyway, so this is only a problem for
legacy code paths that explicitly require thick mode.

## Workbench pod stuck in `Pending` or `ContainerCreating`

**Most common causes:**

- PVC can't be bound → check `oc describe pvc <pvc-name>`. Usually a
  storage-class quota or a zone-affinity mismatch.
- Image pull failing → `oc describe pod <pod-name>`. If the image registry
  needs a pull secret, make sure `default` SA in your namespace has it
  linked:
  ```bash
  oc secrets link default <pull-secret> --for=pull
  ```

## "Database is corrupted" after a pod OOM-kill

Rare but ugly. The SQLite file can be left in an inconsistent state if the
pod is killed during a write.

**Fix**: Run `/opt/scripts/reset-airflow.sh`. You lose DAG run history but
not DAGs themselves.

If this happens repeatedly, you're probably pushing SQLite past its limits.
Switch to the Postgres-backed setup — see `docs/architecture.md`.

## Can't `git push` from the workbench terminal

Check corporate proxy env vars:

```bash
env | grep -i proxy
```

If `HTTP_PROXY` / `HTTPS_PROXY` aren't set, add them to the Notebook CR or
your `~/.bashrc`. For git-over-HTTPS you may also need:

```bash
git config --global http.sslVerify true
git config --global http.proxy "$HTTPS_PROXY"
```
