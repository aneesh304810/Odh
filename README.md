# ODH Code Server + Airflow + dbt-oracle

A custom [Open Data Hub](https://opendatahub.io) Code Server workbench image that
gives every developer their own isolated Apache Airflow 3.1 + dbt-oracle
environment on OpenShift.

Each developer launches a workbench from the ODH dashboard and gets:

- VS Code in the browser (Code Server)
- Airflow standalone running on a per-user PVC (no shared metadata DB)
- dbt-core + dbt-oracle + Astronomer Cosmos pre-installed
- Oracle Instant Client on the image
- A sample DAG and dbt project to verify the environment works end-to-end

Designed for enterprise environments with proxy / mirror constraints
(Nexus, no public PyPI, no Docker Desktop on laptops).

---

## Repository Layout

```
.
├── container/              # Dockerfile + build context
├── scripts/                # Entrypoint + helper scripts baked into the image
├── config/                 # Airflow + dbt config templates
├── manifests/              # OpenShift / ODH manifests
│   ├── base/               # Namespace, RBAC, secrets, PVC defaults
│   └── odh/                # ImageStream + Notebook CR for the ODH dashboard
├── dags/                   # Sample DAGs shipped into the image (read-only seed)
├── dbt_project/            # Sample dbt project
├── docs/                   # Architecture, onboarding, troubleshooting
└── .github/workflows/      # CI: build + push image
```

## Quick Start

### 1. Build and push the image

```bash
make build push IMAGE_TAG=2026.1
```

Or from CI: push to `main` and the GitHub Actions workflow builds and pushes to
the registry defined in the workflow.

### 2. Register the image with ODH

```bash
oc apply -k manifests/odh/
```

This creates the ImageStream the ODH dashboard reads to populate the workbench
image picker.

### 3. Developer workflow

1. Developer opens the ODH dashboard and creates a new workbench
2. Selects **Code Server + Airflow + dbt** from the image list
3. Attaches a PVC (`20Gi` recommended) mounted at `/opt/app-root/src`
4. On first launch, the entrypoint bootstraps Airflow under `$HOME/airflow/`
5. Airflow UI is reachable through the ODH proxy at
   `…/notebook/<ns>/<name>/proxy/8080/`
6. Code Server is the main workbench tab; open a terminal and run
   `airflow dags list` or `dbt run` to verify

See `docs/developer-onboarding.md` for the full developer guide.

## Design Notes

- **Per-user isolation via SQLite + LocalExecutor.** Good enough for DAG
  authoring and unit testing. If a team needs KubernetesExecutor, swap the
  Airflow DB connection to a shared Postgres with per-user schemas (see
  `docs/architecture.md`).
- **No baked-in credentials.** Oracle creds come from per-user Secrets
  referenced by the Notebook CR, rendered into `~/.dbt/profiles.yml` at
  startup via `envsubst`.
- **Proxy-aware build.** The Dockerfile pulls Python packages from a Nexus
  mirror and Oracle Instant Client from an internal artifact repo. Override
  via build args — see `container/Dockerfile`.
- **Reproducible Airflow install.** Uses the official Airflow constraints file
  for the pinned version. Do not `pip install` providers without the
  constraints file or you will break the environment.

## License

Internal — BBH Capital Partners Technology. Not for external distribution.
