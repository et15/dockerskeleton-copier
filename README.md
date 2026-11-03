# services-dockerskeleton

[Copier](https://copier.readthedocs.io/) template for a Docker Compose service
deployed on a systemd- or OpenRC-managed host, with secrets encrypted at rest
via [SOPS](https://github.com/getsops/sops) and conventional-commit tooling
([Commitizen](https://commitizen-tools.github.io/commitizen/) and
[pre-commit](https://pre-commit.com/)) wired up.

What a generated project contains and how it works is documented in
[template/docs/skeleton.md](template/docs/skeleton.md), which is also shipped
into every project as `docs/skeleton.md`.

## Creating a service

```
uv tool install copier
copier copy gh:jdavhessen/services-dockerskeleton my-service
```

Copier asks for the service name, description, install path, init system
(systemd or OpenRC), service user/group and the age public key(s) to encrypt
secrets to, then renders the service file and `.sops.yaml` from them.

## Updating a service

```
cd my-service
copier update
```

Copier records the template version and your answers in
`.copier-answers.yml`. `update` renders both the old and the new template
version with those answers and applies only the difference, so your own edits
are kept; real conflicts show up as regular merge conflict markers. The
working tree must be clean before updating.

`README.md`, `docker-compose.yaml` and `.env` are created once and never
touched by `update`: they belong to the project. Everything else is
maintained by the template, so changes there are best made here.

## Developing the template

```
template/      # everything rendered into a project (*.jinja files are templated)
copier.yml     # questions and Copier settings
```

Copier uses git tags as template versions, and `copier update` moves to the
newest tag, so changes reach projects only once released:

```
cz bump        # updates .cz.toml + CHANGELOG.md, creates the vX.Y.Z tag
git push --follow-tags
```

Try out uncommitted changes with:

```
copier copy --vcs-ref HEAD . /path/to/scratch-project
```

Commit hooks for this repo (same tooling as generated projects; the secrets
check needs `jq` on `PATH`):

```
uv tool install pre-commit
uv tool install commitizen
pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
```
