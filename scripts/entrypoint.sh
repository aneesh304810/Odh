#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# entrypoint.sh
#
# Runs on every workbench pod startup. Responsibilities:
#   1. Seed per-user files from /opt/skel if the PVC is empty
#   2. Export AIRFLOW_HOME / DBT_PROFILES_DIR env vars
#   3. Render ~/.dbt/profiles.yml from template + env
#   4. Initialize Airflow DB (idempotent)
#   5. Start Airflow standalone in background
#   6. Exec the base CMD (code-server) as PID 1 successor
#
# Runs as a non-root user. OpenShift assigns an arbitrary UID at runtime;
# we only rely on group 0 being writable.
# -----------------------------------------------------------------------------
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

HOME_DIR="${HOME:-/opt/app-root/src}"
SKEL_DIR="/opt/skel"

export AIRFLOW_HOME="${AIRFLOW_HOME:-${HOME_DIR}/airflow}"
export AIRFLOW__CORE__DAGS_FOLDER="${AIRFLOW__CORE__DAGS_FOLDER:-${HOME_DIR}/dags}"
export AIRFLOW__CORE__EXECUTOR="${AIRFLOW__CORE__EXECUTOR:-LocalExecutor}"
export AIRFLOW__CORE__LOAD_EXAMPLES="${AIRFLOW__CORE__LOAD_EXAMPLES:-False}"
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN:-sqlite:///${AIRFLOW_HOME}/airflow.db}"
export AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX="${AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX:-True}"
export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-${HOME_DIR}/.dbt}"

# -----------------------------------------------------------------------------
# 1. Seed skeleton on first launch
# -----------------------------------------------------------------------------
seed_if_missing() {
    local src="$1"
    local dst="$2"
    if [[ ! -e "$dst" ]]; then
        log "Seeding ${dst} from ${src}"
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
    else
        log "Keeping existing ${dst}"
    fi
}

seed_if_missing "${SKEL_DIR}/dags"        "${HOME_DIR}/dags"
seed_if_missing "${SKEL_DIR}/dbt_project" "${HOME_DIR}/dbt_project"

mkdir -p "${AIRFLOW_HOME}" "${HOME_DIR}/.dbt" "${HOME_DIR}/logs"

# -----------------------------------------------------------------------------
# 2. Set Airflow webserver base_url to match the ODH proxy path
# -----------------------------------------------------------------------------
if [[ -n "${NB_PREFIX:-}" ]]; then
    # NB_PREFIX looks like: /notebook/my-namespace/my-workbench
    export AIRFLOW__WEBSERVER__BASE_URL="${NB_PREFIX}/proxy/8080"
    log "Airflow BASE_URL set to ${AIRFLOW__WEBSERVER__BASE_URL}"
fi

# -----------------------------------------------------------------------------
# 3. Render dbt profiles.yml from template using env vars
# -----------------------------------------------------------------------------
if [[ -f "${SKEL_DIR}/dbt-config/profiles.yml.tmpl" ]]; then
    envsubst < "${SKEL_DIR}/dbt-config/profiles.yml.tmpl" > "${HOME_DIR}/.dbt/profiles.yml"
    chmod 600 "${HOME_DIR}/.dbt/profiles.yml"
    log "Rendered ${HOME_DIR}/.dbt/profiles.yml"
fi

# -----------------------------------------------------------------------------
# 4. Initialize Airflow DB + admin user (idempotent)
# -----------------------------------------------------------------------------
if [[ ! -f "${AIRFLOW_HOME}/.initialized" ]]; then
    log "First-time Airflow setup in ${AIRFLOW_HOME}"
    airflow db migrate

    ADMIN_USER="${AIRFLOW_ADMIN_USER:-dev}"
    ADMIN_PASS="${AIRFLOW_ADMIN_PASSWORD:-$(openssl rand -hex 12)}"
    airflow users create \
        --username "${ADMIN_USER}" \
        --password "${ADMIN_PASS}" \
        --firstname Developer \
        --lastname User \
        --role Admin \
        --email "${ADMIN_USER}@local" || true

    echo "${ADMIN_PASS}" > "${AIRFLOW_HOME}/.admin_password"
    chmod 600 "${AIRFLOW_HOME}/.admin_password"
    log "Airflow admin user '${ADMIN_USER}' created. Password at ${AIRFLOW_HOME}/.admin_password"

    touch "${AIRFLOW_HOME}/.initialized"
else
    # Apply any schema migrations that shipped with a newer image version.
    airflow db migrate || log "airflow db migrate returned non-zero (likely nothing to do)"
fi

# -----------------------------------------------------------------------------
# 5. Start Airflow standalone in background
# -----------------------------------------------------------------------------
if [[ "${START_AIRFLOW:-true}" == "true" ]]; then
    log "Starting Airflow standalone on :8080"
    nohup airflow standalone \
        > "${HOME_DIR}/logs/airflow-standalone.log" 2>&1 &
    echo $! > "${AIRFLOW_HOME}/standalone.pid"
fi

# -----------------------------------------------------------------------------
# 6. Hand off to code-server (base image CMD)
# -----------------------------------------------------------------------------
log "Handing off to code-server: $*"
exec "$@"
