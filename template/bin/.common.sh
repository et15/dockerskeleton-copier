#!/usr/bin/env bash
# bin/.common.sh - shared helpers for this project's bash scripts.
#
# Source it, don't run it:
#   SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
#   source "${SCRIPT%/*}/.common.sh"
#
# Taken from bin/.common.sh in jdavhessen/services-nginx-jdavhe1, with two
# changes:
#   - Every level logs to stderr, not just ERROR. stdout of
#     bin/dockercompose.sh belongs to `docker compose` (`ps -q`, `config`,
#     ...), so log lines must not end up in it.
#   - FATAL is a known level. Before, it fell back to INFO severity, so it
#     went to stdout and was hidden at LOG_LEVEL=WARN/ERROR.
#
# Requires bash >= 4 (associative arrays, ${var^^}).

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed." >&2
    exit 1
fi

# --- Log level configuration ---
# Numeric severity: lower = more verbose.
declare -A _LOG_LEVELS=( [DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4 )

# LOG_LEVEL sets the minimum level that gets printed. Defaults to INFO if
# unset or invalid.
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_LEVEL="${LOG_LEVEL^^}"

if [[ -z "${_LOG_LEVELS[$LOG_LEVEL]+x}" ]]; then
    echo "[WARN] Invalid LOG_LEVEL='${LOG_LEVEL}', defaulting to INFO" >&2
    LOG_LEVEL="INFO"
fi

# log LEVEL MESSAGE... - print "[timestamp] [LEVEL] MESSAGE" to stderr if
# LEVEL is at or above LOG_LEVEL. Unknown levels count as INFO.
log() {
    local level="${1^^}"
    shift

    local msg_severity="${_LOG_LEVELS[$level]:-${_LOG_LEVELS[INFO]}}"
    local threshold="${_LOG_LEVELS[$LOG_LEVEL]}"

    if (( msg_severity < threshold )); then
        return 0
    fi

    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

log_debug() { log "DEBUG" "$@"; }
log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_fatal() { log "FATAL" "$@"; }

# die MESSAGE... - log MESSAGE as ERROR and exit 1.
die() {
    log_error "$@"
    exit 1
}
