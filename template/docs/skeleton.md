# How this service is wired

This project was generated from
[services-dockerskeleton](https://github.com/jdavhessen/services-dockerskeleton) with
[Copier](https://copier.readthedocs.io/). Everything except `README.md`,
`docker-compose.yaml` and `.env` is maintained by the skeleton, including this
file: pull in its updates with `copier update` rather than editing them in
place, or expect merge conflicts on the next update.

It runs a Docker Compose stack under systemd or OpenRC, with secrets encrypted
at rest via [SOPS](https://github.com/getsops/sops) and conventional-commit
tooling ([Commitizen](https://commitizen-tools.github.io/commitizen/) and
[pre-commit](https://pre-commit.com/)) wired up.

## Layout

```
bin/
  up.sh              # entrypoint: docker compose up -d with secrets decrypted
  dockercompose.sh   # decrypts secrets/*.enc, then runs `docker compose <args>`
  secret-edit.sh     # create/edit a secrets/*.enc via `sops edit`
docker-compose.yaml  # the actual service definition (yours)
.env                 # non-secret values shared by services (yours)
secrets/
  *.enc              # SOPS-encrypted secrets, one value per file (committed)
.sops.yaml           # SOPS creation rule: encrypts secrets/*.enc with your age key(s)
systemd/<app_name>.service   # systemd unit (if generated for systemd)
openrc/<app_name>            # OpenRC init script (if generated for OpenRC)
scripts/
  secrets-env.sh     # entrypoint shim: *_FILE -> env var, for images without _FILE support
  hooks/             # pre-commit hook scripts
docs/skeleton.md     # this file
.copier-answers.yml  # template version + answers, used by `copier update`
.pre-commit-config.yaml
.cz.toml             # Commitizen config (conventional commits, bump, changelog)
```

## Installing the service

The service user must be able to use the Docker socket. Membership in the
`docker` group is effectively root, so the init system's sandboxing doesn't
contain a compromised service.

**systemd:**

```
ln -s <app_path>/systemd/<app_name>.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now <app_name>.service
```

**OpenRC:**

```
ln -s <app_path>/openrc/<app_name> /etc/init.d/<app_name>
rc-update add <app_name> default
rc-service <app_name> start
```

Both read `SOPS_AGE_KEY_FILE` from `/etc/default/sops` if that file exists.

## Secrets

Real secrets never touch the repo in plaintext. Each secret is one encrypted
file under `secrets/`, decrypted at runtime and handed to containers through
Compose's `secrets:` block:

- **Unprotected** values (not secret) go into `.env` (shared by every service
  with `env_file: .env`) or a service's own `environment:`.
- **Protected** values are declared once under the top-level `secrets:` and
  granted per service. Each service sees only the secrets it lists, mounted
  at `/run/secrets/<name>`, and is pointed at them with a `*_FILE` env var:

  ```yaml
  services:
    db:
      image: postgres:17
      environment:
        POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      secrets:
        - db_password

  secrets:
    db_password:
      file: ${SECRETS_DIR:?run via bin/dockercompose.sh}/db_password
  ```

  Compose fails at `up` if a declared secret wasn't decrypted, instead of
  starting the container without it.

To create or edit a secret:

```
bin/secret-edit.sh db_password
```

This opens `$EDITOR` on the decrypted content of `secrets/db_password.enc`
(creating the file if it doesn't exist yet) and re-encrypts on save — the
secret value never touches shell history or a process argument list. Note
that most editors save a trailing newline; images that read `*_FILE` with
`$(cat ...)` strip it, but some apps read it as part of the secret.

`.gitignore` allows `secrets/*.enc` but ignores everything else under
`secrets/`, and the pre-commit hook rejects anything else that gets
force-added there.

### Images without `*_FILE` support

Some images only read secrets from plain env vars. For those, put
`scripts/secrets-env.sh` in front of the image's entrypoint: for every
`FOO_FILE` env var it exports `FOO` with the file's contents, then execs the
original entrypoint. The secret stays out of the container config, so it
doesn't show up in `docker inspect` or `docker compose config`.

```yaml
services:
  app:
    image: example/app:latest
    # Original ENTRYPOINT goes after the shim. Setting `entrypoint:` clears
    # the image's CMD, so repeat it under `command:`. Look both up with:
    #   docker image inspect -f '{{json .Config.Entrypoint}} {{json .Config.Cmd}}' <image>
    entrypoint: ["/bin/sh", "/secrets-env.sh", "/docker-entrypoint.sh"]
    command: ["serve"]
    environment:
      API_TOKEN_FILE: /run/secrets/api_token   # app sees API_TOKEN
    secrets:
      - api_token
    configs:
      - source: secrets-env
        target: /secrets-env.sh
```

The shim needs `/bin/sh` in the image. For shell-less (distroless/scratch)
images, the remaining option is Compose interpolation
(`environment: API_TOKEN: ${API_TOKEN}` with the value exported to the
compose process), which does put the secret into the container config
(`docker inspect`). Use it only as a last resort.

### How it's decrypted at runtime

`bin/dockercompose.sh` (called by `bin/up.sh`, and by the systemd unit or
OpenRC script on start, reload and stop) does the following before invoking
`docker compose`:

1. Picks `$SECRETS_DIR`: `$RUNTIME_DIRECTORY/secrets` when run as a service
   (`/run/<app_name>`, from systemd's `RuntimeDirectory=` or created by the
   OpenRC script), else
   `$XDG_RUNTIME_DIR/<project>/secrets`, else `/run/<project>/secrets`. The
   parent is `0700`, so other host users can't read the secrets; the
   containers reach them through the bind mount regardless.
2. Decrypts every `secrets/*.enc` into `$SECRETS_DIR/<name>` (`.enc` dropped),
   using the age key at `SOPS_AGE_KEY_FILE` (default `/var/sops/age/keys.txt`;
   override it in `/etc/default/sops`).
3. Exports `$SECRETS_DIR` and runs `docker compose -f docker-compose.yaml "$@"`.

The decrypted files stay in place while the stack runs, because containers
can restart at any time and need to find them again. They live on tmpfs and
are removed by `bin/dockercompose.sh down` and when the service stops.
Under systemd the directory must not be under the unit's `PrivateTmp=`: `dockerd`
resolves bind-mount paths in the host's mount namespace and would never see it.

Compose doesn't notice when a secret's content changes. After rotating one,
recreate the services that use it:

```
bin/dockercompose.sh up -d --force-recreate <service>
```

## Running locally

```
bin/up.sh          # docker compose up -d, with secrets decrypted first
bin/dockercompose.sh <any docker compose args>
bin/dockercompose.sh down   # stops the stack and deletes the decrypted secrets
```

Outside systemd the decrypted secrets go to `$XDG_RUNTIME_DIR/<project>/secrets`
and stay there until `down` (or logout/reboot, since it's tmpfs).

Requires `sops` and `docker compose` on `PATH`, plus a readable
`SOPS_AGE_KEY_FILE` (sops handles age keys itself; the `age` tools are only
needed to generate a key with `age-keygen`).

## Development tooling

Commit hooks are managed by the `pre-commit` framework (installed into
`.git/hooks`, not a custom `core.hooksPath`). The `check-secrets` hook also
requires `jq` on `PATH`:

```
uv tool install pre-commit
uv tool install commitizen
pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
```

- **pre-commit stage** — `scripts/hooks/pre-commit-checks.sh` blocks a commit
  if `secrets/*.enc` isn't genuine SOPS output, if anything other than
  `*.enc` is staged under `secrets/`, or if a `.env`/`.env.*` file contains
  a plaintext `PASS`/`SECRET`/`TOKEN`/`API_KEY`/`PRIVATE_KEY` value (`*_FILE`
  keys are exempt, since their value is a path, not the secret). It checks
  the staged content, not the working tree.
- **commit-msg / pre-push** — Commitizen enforces
  [Conventional Commits](https://www.conventionalcommits.org/) and validates
  branch naming.

Bumping a version (updates `.cz.toml`, `CHANGELOG.md`, creates an annotated
tag):

```
cz bump
```
