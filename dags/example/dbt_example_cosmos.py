"""
dbt_example_cosmos.py

Runs the seeded dbt project at ~/dbt_project using Astronomer Cosmos.
Each dbt model becomes its own Airflow task, so failures are isolated and
re-runs are cheap.

Cosmos reads the dbt profile from $DBT_PROFILES_DIR/profiles.yml, which is
rendered by the entrypoint from the per-user Oracle Secret.
"""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from cosmos import DbtDag, ProjectConfig, ProfileConfig, ExecutionConfig
from cosmos.profiles import OracleUserPasswordProfileMapping

HOME = Path(os.environ.get("HOME", "/opt/app-root/src"))
DBT_PROJECT_PATH = HOME / "dbt_project"
DBT_EXECUTABLE = HOME / ".local" / "bin" / "dbt"

profile_config = ProfileConfig(
    profile_name="odh_dev",
    target_name="dev",
    # Cosmos will fall back to the rendered profiles.yml on disk if the
    # profile_mapping is omitted, but specifying it lets us pull creds
    # straight from an Airflow Connection if the developer creates one.
    profile_mapping=OracleUserPasswordProfileMapping(
        conn_id="oracle_default",
        profile_args={"schema": os.environ.get("ORACLE_SCHEMA", "DEV")},
    ),
)

dbt_example_cosmos = DbtDag(
    project_config=ProjectConfig(DBT_PROJECT_PATH.as_posix()),
    profile_config=profile_config,
    execution_config=ExecutionConfig(dbt_executable_path=DBT_EXECUTABLE.as_posix()),
    # Airflow DAG args
    dag_id="dbt_example_cosmos",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["example", "dbt", "cosmos"],
)
