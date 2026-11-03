#!/usr/bin/env bash
# scripts/hooks/pre-commit-checks.sh
set -euo pipefail

fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for pre-commit secrets validation but was not found." >&2
    exit 1
fi

# All checks read the staged blob (":path"), not the working tree, so a
# plaintext file can't slip through by being staged and then overwritten.
# --diff-filter includes R so `git mv plain secrets/x.enc` is checked too.

# --- Hook 0: nothing but *.enc (and .gitkeep) may be committed under secrets/ ---
# .gitignore already ignores the rest, but `git add -f` bypasses it.
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
        secrets/.gitkeep) ;;
        secrets/*/*)
            echo "ERROR: $f: subdirectories under secrets/ are never decrypted by bin/dockercompose.sh." >&2
            fail=1 ;;
        secrets/*.enc) ;;
        *)
            echo "ERROR: $f is under secrets/ but isn't a *.enc file (plaintext secret?)." >&2
            fail=1 ;;
    esac
done < <(git diff --cached --name-only --diff-filter=ACMR -- 'secrets/')

# --- Hook 1: secrets/*.enc must be valid SOPS JSON with 'data' + 'sops' at root ---
while IFS= read -r f; do
    [[ -z "$f" ]] && continue

    content=$(git show ":$f")

    if ! jq empty <<<"$content" >/dev/null 2>&1; then
        echo "ERROR: $f is not valid JSON." >&2
        fail=1
        continue
    fi

    has_data=$(jq 'has("data")' <<<"$content")
    has_sops=$(jq 'has("sops")' <<<"$content")
    has_mac=$(jq '.sops | has("mac")' <<<"$content" 2>/dev/null || echo false)

    if [[ "$has_data" != "true" || "$has_sops" != "true" || "$has_mac" != "true" ]]; then
        echo "ERROR: $f is in secrets/ with a .enc name but doesn't look like real SOPS output (missing 'data', 'sops', or 'sops.mac')." >&2
        fail=1
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR -- 'secrets/*.enc')

# --- Hook 2: plain .env(.*) files must not contain obvious secrets ---
# *_FILE keys are exempt: by convention their value is a path to a decrypted
# secrets/*.enc file (see README.md), not the secret itself.
pattern='(?i)(PASS|SECRET|PASSPHRASE|TOKEN|API_?KEY|PRIVATE_?KEY)[A-Z0-9_]*[[:space:]]*='

while IFS= read -r f; do
    [[ -z "$f" ]] && continue

    matches=$(git show ":$f" | grep -nP "$pattern" || true)
    if [[ -n "$matches" ]]; then
        real=$(echo "$matches" | grep -P '=\s*\S' | grep -viP '_FILE\s*=' || true)
        if [[ -n "$real" ]]; then
            echo "ERROR: $f contains a key matching PASS/SECRET/TOKEN/API_KEY/PRIVATE_KEY with a non-empty value:" >&2
            echo "$real" >&2
            fail=1
        fi
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR -- '*.env' '*.env.*')

if [[ "$fail" -eq 1 ]]; then
    echo "" >&2
    echo "Commit blocked. Encrypt real secrets with sops and move them to secrets/*.enc." >&2
    exit 1
fi

exit 0
