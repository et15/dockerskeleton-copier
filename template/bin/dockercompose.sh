#!/bin/bash
set -euo pipefail

# Anything this script creates is private by default; secret files are
# chmod'ed explicitly below.
umask 077

# Containers read a secret as whatever UID their image defaults to, almost
# never the UID running this script, so secret files are world-readable.
# That is safe because their parent ($SECRETS_BASE) is 0700: host users
# can't traverse into it, while a bind mount exposes the file inside the
# container without walking the host path.
SECRET_FILE_MODE=444
# Ownership to apply to the decrypted secret files, e.g. "1000:1000", so
# SECRET_FILE_MODE can be tightened to 400. Requires running as root.
SECRETS_OWNER="${SECRETS_OWNER:-}"

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPTDIR="${SCRIPT%/*}"
PROJECTDIR="${SCRIPT%/*/*}"
PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PROJECTDIR")}"

# shellcheck source=.common.sh
source "$SCRIPTDIR/.common.sh"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/var/sops/age/keys.txt}"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <docker compose arguments>" >&2
    exit 1
fi

# Decrypted secrets must outlive this script (containers restart, `up -d`
# returns immediately) and must be visible to dockerd, which resolves bind
# mounts in the host mount namespace -- so not a PrivateTmp /tmp. Under
# systemd, RuntimeDirectory= provides $RUNTIME_DIRECTORY (tmpfs, removed
# on stop); interactively, fall back to the per-user runtime dir.
if [[ -n "${RUNTIME_DIRECTORY:-}" ]]; then
    SECRETS_BASE="$RUNTIME_DIRECTORY"
elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    SECRETS_BASE="$XDG_RUNTIME_DIR/$PROJECT"
else
    SECRETS_BASE="/run/$PROJECT"
fi
SECRETS_DIR="$SECRETS_BASE/secrets"
export SECRETS_DIR
log_debug "SECRETS_DIR=$SECRETS_DIR"

# Secrets are removed even if `down` fails (containers still running keep
# the inodes they mounted); the exit code of `docker compose` is kept.
if [[ "$1" == "down" ]]; then
    rc=0
    docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@" || rc=$?
    rm -rf "$SECRETS_DIR"
    log_info "Removed decrypted secrets from $SECRETS_DIR"
    if (( rc != 0 )); then
        log_error "docker compose $* failed (exit $rc)"
    fi
    exit "$rc"
fi

mkdir -p "$SECRETS_BASE"
chmod 700 "$SECRETS_BASE"
mkdir -p "$SECRETS_DIR"
chmod 755 "$SECRETS_DIR"

# Decrypt every secrets/*.enc into $SECRETS_DIR/<name> (same name, .enc dropped).
# docker-compose.yaml declares each one under the top-level `secrets:` block
# (file: ${SECRETS_DIR}/<name>) and grants it per service, which mounts it
# at /run/secrets/<name>.
#
# Each file is written to a temp name and renamed into place, so a running
# container keeps the inode it started with and never sees a half-written
# file. Compose does not notice changed secret content: after rotating a
# secret, run `bin/dockercompose.sh up -d --force-recreate <service>`.
shopt -s nullglob
count=0
for fenc in "$PROJECTDIR"/secrets/*.enc; do
    f="$(basename "${fenc%.enc}")"
    tmp="$SECRETS_DIR/.$f.tmp"

    log_info "Decrypting: secrets/$(basename "$fenc") -> \$SECRETS_DIR/$f"
    if ! sops --input-type binary --output-type binary -d "$fenc" > "$tmp"; then
        rm -f "$tmp"
        die "Failed to decrypt secrets/$(basename "$fenc") (SOPS_AGE_KEY_FILE=$SOPS_AGE_KEY_FILE)"
    fi
    chmod "$SECRET_FILE_MODE" "$tmp"
    [[ -n "$SECRETS_OWNER" ]] && chown "$SECRETS_OWNER" "$tmp"
    mv -f "$tmp" "$SECRETS_DIR/$f"
    count=$((count + 1))
done

log_info "Decrypted $count secret(s) into $SECRETS_DIR"

log_debug "Running: docker compose -f $PROJECTDIR/docker-compose.yaml $*"
docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
