#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_TARGET="${BOOTSTRAP_TARGET:-bolt://tx1:7687}"
EXPECTED_SERVER_COUNT="${EXPECTED_SERVER_COUNT:-5}"
DEFAULT_DATABASE_NAME="${DEFAULT_DATABASE_NAME:-neo4j}"
DEFAULT_DATABASE_TOPOLOGY="${DEFAULT_DATABASE_TOPOLOGY:-3 PRIMARIES 2 SECONDARIES}"
ANALYTICS_SERVER_ADDRESSES="${ANALYTICS_SERVER_ADDRESSES:-localhost:17690,localhost:17691}"

if [[ -z "${NEO4J_PASSWORD:-}" ]]; then
  echo "[cluster-init] NEO4J_PASSWORD is required" >&2
  exit 1
fi

log() {
  echo "[cluster-init] $*"
}

run_cypher() {
  cypher-shell \
    --non-interactive \
    --format plain \
    -a "${BOOTSTRAP_TARGET}" \
    -u neo4j \
    -p "${NEO4J_PASSWORD}" \
    -d system \
    "$1"
}

query_value() {
  local result
  result="$(run_cypher "$1" | awk 'NF { last=$0 } END { gsub(/\r/, "", last); print last }')"
  result="${result#\"}"
  result="${result%\"}"

  if [[ "${result}" == "value" ]]; then
    echo ""
    return 0
  fi

  echo "${result}"
}

wait_for_servers() {
  local visible

  while true; do
    visible="$(query_value "SHOW SERVERS YIELD address RETURN count(*) AS value")"

    if [[ "${visible}" == "${EXPECTED_SERVER_COUNT}" ]]; then
      log "All ${EXPECTED_SERVER_COUNT} cluster members are visible."
      return 0
    fi

    log "Waiting for cluster discovery. Visible servers: ${visible:-0}/${EXPECTED_SERVER_COUNT}"
    sleep 5
  done
}

enable_analytics_server() {
  local address="$1"
  local name
  local state

  while true; do
    name="$(query_value "SHOW SERVERS YIELD name, address WHERE address = '${address}' RETURN name AS value")"
    state="$(query_value "SHOW SERVERS YIELD state, address WHERE address = '${address}' RETURN state AS value")"

    if [[ -z "${name}" || -z "${state}" ]]; then
      log "Waiting for server record ${address}."
      sleep 5
      continue
    fi

    if [[ "${state}" == "Enabled" ]]; then
      log "Server ${name} (${address}) already enabled."
      return 0
    fi

    if [[ "${state}" == "Free" ]]; then
      log "Enabling analytics server ${name} (${address})."
      run_cypher "ENABLE SERVER '${name}'" >/dev/null
      sleep 5
      continue
    fi

    log "Server ${name} (${address}) currently ${state}, waiting."
    sleep 5
  done
}

wait_for_enabled_analytics() {
  local address
  local state

  while true; do
    local all_enabled="true"

    IFS=',' read -ra ADDRESSES <<< "${ANALYTICS_SERVER_ADDRESSES}"
    for address in "${ADDRESSES[@]}"; do
      state="$(query_value "SHOW SERVERS YIELD state, address WHERE address = '${address}' RETURN state AS value")"

      if [[ "${state}" != "Enabled" ]]; then
        all_enabled="false"
        log "Analytics member ${address} still ${state:-unknown}."
      fi
    done

    if [[ "${all_enabled}" == "true" ]]; then
      log "All analytics members are enabled."
      return 0
    fi

    sleep 5
  done
}

set_database_topology() {
  log "Ensuring ${DEFAULT_DATABASE_NAME} uses topology ${DEFAULT_DATABASE_TOPOLOGY}."
  run_cypher "ALTER DATABASE ${DEFAULT_DATABASE_NAME} IF EXISTS SET TOPOLOGY ${DEFAULT_DATABASE_TOPOLOGY} WAIT 300 SECONDS" >/dev/null
}

show_summary() {
  log "Final server state:"
  run_cypher "SHOW SERVERS YIELD name, address, state, hosting RETURN name, address, state, hosting" || true
}

main() {
  wait_for_servers

  IFS=',' read -ra ADDRESSES <<< "${ANALYTICS_SERVER_ADDRESSES}"
  for address in "${ADDRESSES[@]}"; do
    enable_analytics_server "${address}"
  done

  wait_for_enabled_analytics
  set_database_topology
  show_summary
  log "Analytics cluster bootstrap finished."
}

main "$@"
