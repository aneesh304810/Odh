#!/usr/bin/env bash
# reset-airflow.sh
#
# Blow away the developer's Airflow state (metadata DB, logs, pid file) and
# re-run the bootstrap. Useful when DAGs get stuck or the SQLite file locks up.
#
# Does NOT touch DAG source files under ~/dags or dbt projects.
set -euo pipefail

AIRFLOW_HOME="${AIRFLOW_HOME:-$HOME/airflow}"

echo "About to remove Airflow state under ${AIRFLOW_HOME}"
read -r -p "Continue? [y/N] " reply
[[ "${reply,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# Stop running Airflow if present
if [[ -f "${AIRFLOW_HOME}/standalone.pid" ]]; then
    pid=$(cat "${AIRFLOW_HOME}/standalone.pid")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping Airflow (pid=$pid)"
        kill "$pid" || true
        sleep 3
    fi
fi

# Also kill any lingering airflow processes for this user
pkill -u "$(id -u)" -f "airflow " || true

rm -rf "${AIRFLOW_HOME}/airflow.db" \
       "${AIRFLOW_HOME}/.initialized" \
       "${AIRFLOW_HOME}/.admin_password" \
       "${AIRFLOW_HOME}/logs" \
       "${AIRFLOW_HOME}/standalone.pid"

echo "Re-running entrypoint to bootstrap Airflow"
exec /opt/scripts/entrypoint.sh sleep 0
