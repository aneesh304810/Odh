# Architecture

## Goals

- Every developer gets an **isolated** Airflow + dbt environment — no shared
  metadata DB, no "who broke the scheduler today" incidents.
- Developers run in the ODH dashboard they already use, not yet another
  separate platform.
- The BBH network constraints (blocked PyPI, no Docker Desktop, Nexus proxy)
  are handled at build time so developers never hit them at runtime.
- The same image ships to all developers — reproducibility is non-negotiable
  given the SWP migration audit requirements.

## Component diagram

```
+--------------------------+
| ODH Dashboard            |
|  (workbench image picker)|
+-----------+--------------+
            |
            | creates Notebook CR
            v
+--------------------------+       +-----------------------------+
| Workbench Pod            |-----> | PVC (RWO, 20Gi)             |
|                          |       |  /opt/app-root/src          |
|  container: code-server  |       |  - airflow/  (metadata DB)  |
|  entrypoint.sh           |       |  - dags/                    |
|   ├─ seed skeleton       |       |  - dbt_project/             |
|   ├─ render profiles.yml |       |  - .dbt/profiles.yml        |
|   ├─ airflow db migrate  |       |  - logs/                    |
|   ├─ airflow standalone  |       +-----------------------------+
|   └─ exec code-server    |
|                          |       +-----------------------------+
|  envFrom:                |<----- | Secret: oracle-dev          |
|   oracle-dev (Secret)    |       |  ORACLE_HOST, _USER, _PASS  |
+--------------------------+       +-----------------------------+
   |                |
   | :8787          | :8080
   v                v
 code-server UI   Airflow UI
 (primary tab)    (proxy/8080)
```

## Why SQLite + LocalExecutor per user

The decision space is:

| Option | Isolation | Ops burden | Fidelity to prod |
|---|---|---|---|
| Shared Airflow, shared metadata | none | low | low |
| Shared Airflow, per-user namespaces | moderate | high | high |
| **Per-user Airflow standalone (this)** | full | low | medium |

The per-user approach wins for a **dev environment**. Developers author DAGs
and test dbt models; they don't need to simulate the prod KubernetesExecutor
cluster locally. When they're ready to validate against production patterns,
they push to the shared pre-prod Airflow (separate infra, outside this repo).

SQLite is fine because:
- LocalExecutor uses in-process parallelism — no need for the DB to coordinate
  across workers.
- A single developer authoring DAGs almost never generates enough concurrent
  writes to hit SQLite's write lock.
- PVC snapshots give us a trivial backup/restore story.

## When to switch to Postgres

If any of these become true, graduate the environment to a per-user schema
on a shared Postgres:

- Developers routinely run >10 parallel tasks and hit SQLite lock contention
- Teams want to share DAG runs / XCom between workbenches
- Compliance requires centralized audit logging of Airflow metadata

The `entrypoint.sh` already reads
`AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` from the environment, so the switch is
a Notebook-CR-level change, not an image rebuild.

## Security model

- **No credentials in the image.** Oracle credentials come from per-user
  Secrets, injected via `envFrom` at pod creation, rendered into
  `profiles.yml` by the entrypoint. The rendered file is `chmod 600`.
- **Arbitrary UID compatible.** OpenShift assigns a random UID at runtime;
  everything the image writes lives under group 0, which is always writable.
- **No baked-in Airflow admin password.** Generated randomly on first launch
  if not provided via `AIRFLOW_ADMIN_PASSWORD`, written to a `chmod 600`
  file inside the PVC.
- **ServiceAccount scoped.** Reads only its own namespace's Secrets and
  ConfigMaps, plus pod create/delete for the KubernetesExecutor opt-in path.

## Relationship to SWP migration

This is a **developer** environment, not a runtime target for the SWP
migration workloads. The production Airflow/dbt deployment for SWP runs
on the 10-node OpenShift production cluster described in the CTO deck
(96 vCPU / 192GB RAM, KEDA-autoscaled KubernetesExecutor, shared Postgres
metadata). This image lets developers build and test DAGs for that
environment before promoting.
