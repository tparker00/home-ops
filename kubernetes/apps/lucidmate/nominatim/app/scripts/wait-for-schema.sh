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
# Auth failure must not masquerade as "schema not present" -- that turned a
# CNPG managed-role password drift into an endless init loop (2026-11-07).
# Count consecutive auth failures; after 10 (~2.5 min) give up loudly so
# the pod restarts and the reason is visible in events, not a silent loop.
auth_failures=0
while true; do
  if ! psql -h "${PGHOST}" -d postgres -U "${PGUSER}" -Atqc "SELECT 1" >/dev/null 2>&1; then
    auth_failures=$((auth_failures + 1))
    if [ "${auth_failures}" -ge 10 ]; then
      log "FATAL: cannot authenticate to ${PGHOST} as ${PGUSER} for 10 consecutive checks -- check CNPG managed-role password reconciliation"
      exit 1
    fi
    log "auth/connect failure (${auth_failures}/10) -- not treating as missing schema"
  else
    auth_failures=0
    has_placex="$(psql -h "${PGHOST}" -d "${PGDATABASE}" -U "${PGUSER}" -Atqc "${GUARD_SQL}" 2>/dev/null || echo f)"
    if [ "${has_placex}" = "t" ]; then
      log "schema present; proceeding"
      exit 0
    fi
    log "schema not yet present (bootstrap job likely still running); waiting"
  fi
  sleep 15
done
