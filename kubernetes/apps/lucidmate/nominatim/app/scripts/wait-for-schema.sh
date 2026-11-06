#!/bin/bash
# Blocks the main nominatim container from starting until the schema
# exists (placex table present). Prevents a race between the bootstrap
# job's import/indexing and start-external.sh's unconditional
# `nominatim refresh --functions` -- concurrent DDL against a live
# import caused repeated "cache lookup failed for function N" crashes
# during the 2026-11-06 bootstrap (confirmed live: the collision only
# disappeared once the deployment was scaled to 0 during the import).
#
# Once the schema exists (the common case after the first bootstrap),
# this exits immediately -- zero added startup latency.
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
PGDATABASE="${PGDATABASE:-nominatim}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

log() { echo "[wait-for-schema] $*"; }

until pg_isready -h "${PGHOST}" -U "${PGUSER}" -q; do
  log "waiting for PostgreSQL at ${PGHOST}"
  sleep 5
done

GUARD_SQL="SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'placex' AND c.relkind = 'r')"
while true; do
  has_placex="$(psql -h "${PGHOST}" -d "${PGDATABASE}" -U "${PGUSER}" -Atqc "${GUARD_SQL}" 2>/dev/null || echo f)"
  if [ "${has_placex}" = "t" ]; then
    log "schema present; proceeding"
    exit 0
  fi
  log "schema not yet present (bootstrap job likely still running); waiting"
  sleep 15
done
