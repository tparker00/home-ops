#!/bin/bash
# Idempotent fresh-cluster bootstrap for external-DB Nominatim.
#
# Run by the `bootstrap` job controller (app-template) — fires on every
# HelmRelease apply; the guard below makes re-runs no-ops once data exists.
# Prerequisites (CREATEDB, www-data role, template1 extensions) are
# provisioned by the CNPG cluster's postInit* hooks — see
# kubernetes/apps/database/cloudnative-pg/clusters/nominatim/postgres.yaml.
#
# Contract (verified against nominatim_db 5.3.2 source):
#   - `nominatim import` always createdb's its own database (fails if it
#     exists); the empty database CNPG's initdb creates must be dropped.
#   - It installs hstore/postgis/postgis_raster via CREATE EXTENSION IF NOT
#     EXISTS; template1 carries them, so the import's statements no-op for
#     the database owner. There is no --dsn flag in 5.3.2 — the DSN comes
#     from the NOMINATIM_DATABASE_DSN env (preserved through sudo -E).
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/nominatim}"
STAGING="${IMPORT_STAGING:-/import-staging}"
SEED_REGION="${NOMINATIM_BOOTSTRAP_REGION:-north-america/us/new-jersey}"
DOWNURL="${NOMINATIM_DOWNURL:-https://download.geofabrik.de}"
THREADS="${NOMINATIM_IMPORT_THREADS:-8}"
: "${NOMINATIM_DATABASE_DSN:?NOMINATIM_DATABASE_DSN is required}"
: "${PGHOST:?PGHOST is required}"
PGDATABASE="${PGDATABASE:-nominatim}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

log() { echo "[nominatim-bootstrap] $*"; }

until pg_isready -h "${PGHOST}" -d "${PGDATABASE}" -U "${PGUSER}" -q; do
  log "waiting for PostgreSQL at ${PGHOST}"; sleep 5
done

# Idempotency guard: a previous import already built the schema -> no-op.
# A missing database (dropped by an interrupted prior run) counts as "not
# imported" -- but an AUTH failure must never be mistaken for "no schema":
# that once let this job try DROP DATABASE against a fully populated DB
# (2026-11-07: CNPG managed-role password drifted from the secret; the
# guard's psql failed auth, was read as "no placex", and only the DROP's
# own auth failure saved the data). Distinguish the two: connect to
# 'postgres' (always exists) first; if that fails, die loudly.
GUARD_SQL="SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'placex' AND c.relkind = 'r')"
if ! psql -h "${PGHOST}" -d postgres -U "${PGUSER}" -Atqc "SELECT 1" >/dev/null 2>&1; then
  log "FATAL: cannot authenticate/connect to ${PGHOST} as ${PGUSER}; refusing to proceed (this is NOT a missing-schema condition)"
  exit 1
fi
has_placex="$(psql -h "${PGHOST}" -d "${PGDATABASE}" -U "${PGUSER}" -Atqc "${GUARD_SQL}" 2>/dev/null || echo f)"
if [ "${has_placex}" = "t" ]; then
  log "placex already present; nothing to do"
  exit 0
fi

# mediagis conventions: unprivileged OS user owns the project dir.
id nominatim >/dev/null 2>&1 || useradd -m nominatim
chown -R nominatim:nominatim "${PROJECT_DIR}"
mkdir -p "${STAGING}"

# Seed .env (the image's default is baked under /nominatim, hidden by the
# PVC mount).
if [ ! -f "${PROJECT_DIR}/.env" ]; then
  cp /scripts/env.defaults "${PROJECT_DIR}/.env"
fi
sed -i "s|__IMPORT_STYLE__|${IMPORT_STYLE:-extratags}|g" "${PROJECT_DIR}/.env"
sed -i "s|__REPLICATION_URL__|${REPLICATION_URL:-}|g" "${PROJECT_DIR}/.env"

# Drop the empty database CNPG's initdb created — the import insists on
# creating its own (connected to the `postgres` db; we own the target).
log "dropping empty ${PGDATABASE} database (pre-created by CNPG initdb)"
psql -h "${PGHOST}" -d postgres -U "${PGUSER}" -c "DROP DATABASE IF EXISTS ${PGDATABASE};"

# Seed region PBF.
log "downloading seed region ${SEED_REGION}"
curl -L -C - --fail -A nominatim-bootstrap \
  "${DOWNURL}/${SEED_REGION}-latest.osm.pbf" -o "${STAGING}/data.osm.pbf"
ln -sfn "${STAGING}/data.osm.pbf" "${PROJECT_DIR}/data.osm.pbf"

log "running nominatim import (seed: ${SEED_REGION})"
sudo -E -u nominatim nominatim import \
  --project-dir "${PROJECT_DIR}" \
  --osm-file "${PROJECT_DIR}/data.osm.pbf" \
  --offline --threads "${THREADS}"

# Ledger: the designed add-region machinery (maintain-regions.sh) must skip
# the seed region when adding the rest.
echo "${SEED_REGION}" >> "${PROJECT_DIR}/imported-regions.txt"
chown nominatim:nominatim "${PROJECT_DIR}/imported-regions.txt"

log "bootstrap complete — deployment seeds import-finished on next start"
