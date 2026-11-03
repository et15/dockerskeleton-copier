#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPTDIR="${SCRIPT%/*}"

"$SCRIPTDIR/dockercompose.sh" up -d
