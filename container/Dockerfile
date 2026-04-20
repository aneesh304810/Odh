# syntax=docker/dockerfile:1.6
#
# Code Server + Airflow + dbt-oracle image for Open Data Hub.
#
# Base: ODH upstream codeserver workbench image (UBI 9, Python 3.11).
# Ships with VS Code / code-server on port 8787.
#
# We add:
#   - Oracle Instant Client (basiclite)
#   - Airflow 3.x + providers (Oracle, Kubernetes)
#   - dbt-core, dbt-oracle, Astronomer Cosmos
#   - Bootstrap entrypoint that initializes Airflow per-user on the PVC
#
# Build args are parameterised so the same Dockerfile works for public and
# air-gapped (Nexus-backed) builds. Defaults assume the BBH Nexus mirror.
#
ARG BASE_IMAGE=quay.io/opendatahub/workbench-images:codeserver-ubi9-python-3.11-latest
FROM ${BASE_IMAGE}

ARG NEXUS_URL=https://nexus.bbh.com
ARG AIRFLOW_VERSION=3.1.7
ARG PYTHON_VERSION=3.11
ARG DBT_VERSION=1.8.9
ARG DBT_ORACLE_VERSION=1.8.3
ARG COSMOS_VERSION=1.7.0
ARG ORACLE_IC_VERSION=21.13.0.0.0
ARG ORACLE_IC_ZIP=instantclient-basiclite-linux.x64-${ORACLE_IC_VERSION}dbru.zip

LABEL org.opencontainers.image.title="Code Server + Airflow + dbt" \
      org.opencontainers.image.description="ODH workbench with per-user Airflow and dbt-oracle" \
      org.opencontainers.image.vendor="BBH Capital Partners Technology" \
      io.openshift.expose-services="8787:http,8080:http" \
      io.k8s.display-name="Code Server + Airflow + dbt"

# ---------------------------------------------------------------------------
# Root layer: system packages + Oracle Instant Client
# ---------------------------------------------------------------------------
USER 0

RUN dnf install -y --setopt=tsflags=nodocs \
        libaio \
        unzip \
        gcc \
        gcc-c++ \
        make \
        git \
        jq \
        procps-ng \
        gettext \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Oracle Instant Client. Pulled from Nexus raw repository in enterprise
# builds; override ORACLE_IC_URL for public/OSS builds.
ARG ORACLE_IC_URL=${NEXUS_URL}/repository/oracle-raw/${ORACLE_IC_ZIP}
RUN mkdir -p /opt/oracle \
    && curl -fsSL -o /tmp/ic.zip "${ORACLE_IC_URL}" \
    && unzip -q /tmp/ic.zip -d /opt/oracle \
    && rm /tmp/ic.zip \
    && INSTANT_CLIENT_DIR=$(find /opt/oracle -maxdepth 1 -type d -name 'instantclient_*' | head -n1) \
    && ln -s "${INSTANT_CLIENT_DIR}" /opt/oracle/instantclient \
    && echo /opt/oracle/instantclient > /etc/ld.so.conf.d/oracle.conf \
    && ldconfig

ENV LD_LIBRARY_PATH=/opt/oracle/instantclient \
    PATH=/opt/oracle/instantclient:${PATH} \
    TNS_ADMIN=/opt/oracle/instantclient/network/admin

# ---------------------------------------------------------------------------
# Non-root layer: Python packages
# ---------------------------------------------------------------------------
USER 1001
WORKDIR /opt/app-root/src

# Point pip at Nexus before anything else
COPY --chown=1001:0 config/pip.conf /opt/app-root/src/.config/pip/pip.conf

ENV AIRFLOW_HOME=/opt/app-root/src/airflow \
    AIRFLOW__CORE__LOAD_EXAMPLES=False \
    AIRFLOW__CORE__EXECUTOR=LocalExecutor \
    AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX=True \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Airflow must be installed WITH its constraints file. Installing providers
# without constraints will silently break transitive dependencies.
ARG AIRFLOW_CONSTRAINTS_URL=${NEXUS_URL}/repository/airflow-constraints/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt

RUN pip install --user \
        "apache-airflow==${AIRFLOW_VERSION}" \
        --constraint "${AIRFLOW_CONSTRAINTS_URL}"

RUN pip install --user \
        --constraint "${AIRFLOW_CONSTRAINTS_URL}" \
        "apache-airflow-providers-oracle" \
        "apache-airflow-providers-cncf-kubernetes" \
        "apache-airflow-providers-postgres" \
        "apache-airflow-providers-common-sql"

# dbt-oracle and Cosmos. These are pinned independently of the Airflow
# constraints file because dbt has its own dependency graph.
RUN pip install --user \
        "dbt-core==${DBT_VERSION}" \
        "dbt-oracle==${DBT_ORACLE_VERSION}" \
        "astronomer-cosmos[dbt-oracle]==${COSMOS_VERSION}" \
        "oracledb" \
        "great-expectations"

# Make ~/.local/bin authoritative for airflow, dbt, etc.
ENV PATH=/opt/app-root/src/.local/bin:${PATH}

# ---------------------------------------------------------------------------
# Bake entrypoint + skeleton assets
#
# The PVC will be mounted at /opt/app-root/src and will shadow anything we
# write here at build time. So we stage skeleton content at /opt/skel and
# rsync it into $HOME on first launch (only if $HOME is empty).
# ---------------------------------------------------------------------------
USER 0

RUN mkdir -p /opt/skel /opt/scripts \
    && chown -R 1001:0 /opt/skel /opt/scripts

COPY --chown=1001:0 scripts/           /opt/scripts/
COPY --chown=1001:0 dags/              /opt/skel/dags/
COPY --chown=1001:0 dbt_project/       /opt/skel/dbt_project/
COPY --chown=1001:0 config/airflow/    /opt/skel/airflow-config/
COPY --chown=1001:0 config/dbt/        /opt/skel/dbt-config/

RUN chmod +x /opt/scripts/*.sh

USER 1001

EXPOSE 8787 8080

# Override the ODH base entrypoint so we can bootstrap Airflow before
# handing control back to code-server.
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["/opt/app-root/bin/run-code-server.sh"]
