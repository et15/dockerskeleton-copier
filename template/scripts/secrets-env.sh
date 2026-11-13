#!/bin/sh
# scripts/secrets-env.sh
#
# Entrypoint shim for images that only read secrets from env vars, not from
# *_FILE paths. Mounted into the container via docker-compose.yaml `configs:`
# and placed in front of the image's original entrypoint:
#
#   entrypoint: ["/bin/sh", "/secrets-env.sh", "<original ENTRYPOINT...>"]
#   command:    [<original CMD...>]
#
# For every FOO_FILE env var it exports FOO with the file's contents
# (trailing newlines stripped), unsets FOO_FILE, then execs "$@". The secret
# reaches the process environment only inside the container, never the
# container config, so it doesn't show up in `docker inspect`.
#
# POSIX sh only: must run on busybox/alpine as well as debian-based images.
set -eu

# Names are restricted to [A-Za-z_][A-Za-z0-9_]*, so the evals below only
# ever see identifiers, never values.
for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)_FILE=.*/\1/p'); do
    eval "file=\${${name}_FILE-}"
    [ -n "$file" ] || continue

    eval "already_set=\${${name}+x}"
    if [ -n "$already_set" ]; then
        echo "secrets-env: both $name and ${name}_FILE are set, refusing to guess" >&2
        exit 1
    fi
    if [ ! -r "$file" ]; then
        echo "secrets-env: ${name}_FILE=$file is not readable" >&2
        exit 1
    fi

    value=$(cat "$file")
    export "$name=$value"
    unset "${name}_FILE"
done
unset name file already_set value

if [ "$#" -eq 0 ]; then
    echo "secrets-env: no command given; set entrypoint/command in docker-compose.yaml" >&2
    exit 1
fi

exec "$@"
