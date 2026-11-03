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
PROJECTDIR="${SCRIPT%/*/*}"
PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PROJECTDIR")}"

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

if [[ "$1" == "down" ]]; then
    docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
    rm -rf "$SECRETS_DIR"
    exit 0
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

    echo "Decrypting: secrets/$(basename "$fenc") -> \$SECRETS_DIR/$f" >&2
    if ! sops --input-type binary --output-type binary -d "$fenc" > "$tmp"; then
        rm -f "$tmp"
        exit 1
    fi
    chmod "$SECRET_FILE_MODE" "$tmp"
    [[ -n "$SECRETS_OWNER" ]] && chown "$SECRETS_OWNER" "$tmp"
    mv -f "$tmp" "$SECRETS_DIR/$f"
    count=$((count + 1))
done

echo "Decrypted $count secret(s) into $SECRETS_DIR" >&2

docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
