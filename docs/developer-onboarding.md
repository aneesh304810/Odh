# Developer Onboarding

Five-minute guide to getting your workbench running.

## 1. Request an Oracle dev schema

Open a ticket with the DBA team (or use the self-service portal if your team
has one). You'll get back five values:

- `ORACLE_HOST`
- `ORACLE_PORT` (usually `1521`)
- `ORACLE_SERVICE`
- `ORACLE_USER`
- `ORACLE_PASSWORD`

## 2. Create your credentials Secret

In your ODH user namespace (usually `rhods-notebooks` or your team's):

```bash
oc create secret generic oracle-dev \
  --from-literal=ORACLE_HOST=oracledev.bbh.com \
  --from-literal=ORACLE_PORT=1521 \
  --from-literal=ORACLE_SERVICE=DEVPDB \
  --from-literal=ORACLE_USER="$ORACLE_USER" \
  --from-literal=ORACLE_PASSWORD="$ORACLE_PASSWORD" \
  --from-literal=ORACLE_SCHEMA="$ORACLE_USER"
```

Verify:

```bash
oc get secret oracle-dev -o jsonpath='{.data.ORACLE_USER}' | base64 -d
```

## 3. Create the workbench in ODH

1. Open the ODH dashboard (Red Hat OpenShift AI or upstream ODH)
2. **Data Science Projects** → pick your project → **Create workbench**
3. Fill in:
   - **Name**: something like `<your-name>-codeserver`
   - **Image selection**: **Code Server + Airflow + dbt** (version `2026.1`)
   - **Container size**: Small (1 CPU / 4Gi) or Medium (2 CPU / 8Gi)
   - **Storage**: 20Gi persistent volume
4. Under **Environment variables** → **Add variable** → **Secret** →
   select `oracle-dev`, choose **Key / value from a Secret** →
   tick all five `ORACLE_*` keys
5. Click **Create workbench**

First launch takes 60–90 seconds because the entrypoint seeds the PVC and
initializes the Airflow metadata DB.

## 4. Access the two UIs

Once the workbench is Running:

- **Code Server (primary)** — click **Open** in the dashboard. You land in
  VS Code in the browser at `/opt/app-root/src`.
- **Airflow UI** — open a new browser tab and append `/proxy/8080/` to your
  workbench URL. For example:

      https://odh.apps.cluster.bbh.com/notebook/rhods-notebooks/aneesh-codeserver/proxy/8080/

  Username is your `AIRFLOW_ADMIN_USER` env var (defaults to `dev`). Find
  the generated password at `~/airflow/.admin_password`:

  ```bash
  cat ~/airflow/.admin_password
  ```

## 5. Verify end-to-end

Open a terminal in Code Server and run:

```bash
# Airflow
airflow dags list
airflow dags trigger hello_airflow

# Oracle connectivity
bash /opt/scripts/test-oracle.sh

# dbt
cd ~/dbt_project
dbt deps
dbt debug
dbt run --select my_first_model
```

If all four succeed, you're ready to build real DAGs.

## 6. Day-to-day workflow

- **Write DAGs** under `~/dags/`. Airflow picks them up automatically
  (scan interval ~30s). Watch the scheduler log at
  `~/logs/airflow-standalone.log` if a DAG doesn't appear.
- **Edit dbt models** under `~/dbt_project/`. Run `dbt run` from the
  terminal, or trigger the `dbt_example_cosmos` DAG to execute them
  through Airflow.
- **Use git.** The PVC is yours — clone your repos straight into `~/` and
  commit from the Code Server terminal. Configure git once:
  ```bash
  git config --global user.name  "Your Name"
  git config --global user.email "your@bbh.com"
  ```

## 7. When things break

Start with [troubleshooting.md](./troubleshooting.md). The two most common
knobs:

- **Airflow UI redirects to the wrong path** → confirm `NB_PREFIX` is set on
  the pod (`oc describe pod <workbench-pod> | grep NB_PREFIX`).
- **SQLite database is locked** → run `/opt/scripts/reset-airflow.sh` to
  wipe metadata and re-bootstrap. Your DAG files are untouched.

## 8. What's next

When your DAGs are stable and you want them running on a real schedule
against production data, promote them to the shared pre-prod Airflow
(separate process — talk to the data platform team). This workbench is
development only.
