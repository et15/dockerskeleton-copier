## v0.3.0 (2026-11-03)

### Feat

- per-service compose secrets and an env-var shim for non-_FILE images

### Fix

- reject secret names that could escape secrets/
- keep decrypted secrets in a runtime dir dockerd can see
- close bypasses in the pre-commit secrets check

## v0.2.1 (2026-08-06)

### Fix

- respect SOPS_AGE_KEY_FILE override, open secret perms for non-root containers
- allow secrets/*.enc to actually be committed

## v0.2.0 (2026-08-06)

### Feat

- add bin/secret-edit.sh to create/edit secrets via sops edit
- document the secrets bind-mount convention with an example .env

### Fix

- decrypt secrets/*.enc into a bind-mountable dir, not the old envfiles list
- point pre-commit hook at its new path, exempt *_FILE keys from secret scan

## v0.1.0 (2026-08-06)

### Feat

- switch secrets to a single encrypted secrets/*.enc scheme

## v0.0.2 (2026-08-05)

### Fix

- clean up temp files on TERM/INT and match .enc.env suffix precisely

### Refactor

- move env-decrypt/compose logic into dockercompose.sh, have up.sh call it
