# Makefile for ODH Code Server + Airflow + dbt image
#
# Usage:
#   make build                # build locally
#   make push                 # push to REGISTRY
#   make build push IMAGE_TAG=2026.1

REGISTRY       ?= image-registry.openshift-image-registry.svc:5000
NAMESPACE      ?= odh-images
IMAGE_NAME     ?= codeserver-airflow-dbt
IMAGE_TAG      ?= dev
IMAGE          := $(REGISTRY)/$(NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG)

# Build args — override with make build NEXUS_URL=https://...
NEXUS_URL         ?= https://nexus.bbh.com
AIRFLOW_VERSION   ?= 3.1.7
PYTHON_VERSION    ?= 3.11
DBT_VERSION       ?= 1.8.9
DBT_ORACLE_VERSION?= 1.8.3
COSMOS_VERSION    ?= 1.7.0

.PHONY: build push apply clean lint help

help:
	@echo "Targets:"
	@echo "  build   - Build the container image locally"
	@echo "  push    - Push the image to \$$REGISTRY"
	@echo "  apply   - Apply ODH manifests to the current oc context"
	@echo "  lint    - Lint Dockerfile and shell scripts"
	@echo "  clean   - Remove local image"

build:
	podman build \
	  --build-arg NEXUS_URL=$(NEXUS_URL) \
	  --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) \
	  --build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
	  --build-arg DBT_VERSION=$(DBT_VERSION) \
	  --build-arg DBT_ORACLE_VERSION=$(DBT_ORACLE_VERSION) \
	  --build-arg COSMOS_VERSION=$(COSMOS_VERSION) \
	  -t $(IMAGE) \
	  -f container/Dockerfile .

push:
	podman push $(IMAGE)

apply:
	oc apply -k manifests/base/
	oc apply -k manifests/odh/

lint:
	hadolint container/Dockerfile
	shellcheck scripts/*.sh

clean:
	podman rmi $(IMAGE) || true
