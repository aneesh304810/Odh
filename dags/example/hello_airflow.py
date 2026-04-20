"""
hello_airflow.py

Simplest possible DAG — verifies Airflow is running correctly on the
developer's workbench. Prints the current Airflow version and the developer's
username, then completes.

Runs once when manually triggered.
"""

from __future__ import annotations

import getpass
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator


def say_hello() -> None:
    import airflow
    print(f"Hello from Airflow {airflow.__version__}!")
    print(f"Running as user: {getpass.getuser()}")


with DAG(
    dag_id="hello_airflow",
    description="Smoke test: verify the workbench Airflow install",
    start_date=datetime(2026, 1, 1),
    schedule=None,  # manual trigger only
    catchup=False,
    tags=["example", "smoke-test"],
) as dag:
    PythonOperator(
        task_id="say_hello",
        python_callable=say_hello,
    )
