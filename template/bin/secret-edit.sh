#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
PROJECTDIR="${SCRIPT%/*/*}"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/var/sops/age/keys.txt}"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <secret-name>" >&2
    echo "Opens \$EDITOR on secrets/<secret-name>.enc (creates it if new), encrypting on save." >&2
    exit 1
fi

# Keeps the name usable as a compose secret name and prevents writing
# outside secrets/ (e.g. "../foo").
if [[ ! "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    echo "Invalid secret name: '$1' (allowed: letters, digits, '_', '.', '-')" >&2
    exit 1
fi

mkdir -p "$PROJECTDIR/secrets"
sops --input-type binary --output-type binary edit "$PROJECTDIR/secrets/$1.enc"
