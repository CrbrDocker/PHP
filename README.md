# apache-php

Apache + PHP images built on top of the crbr Debian base
(`crbrdocker/debian:stable`), multi-arch (`amd64` + `arm64`), published by CI to
**GHCR** (`ghcr.io/crbrdocker/apache-php`) and **Docker Hub**
(`crbrdocker/apache-php`), one tag per PHP version (`:8.3`, `:8.4`, `:8.5`, …).
Rebuilt weekly, but only when something changed. The previous manual
implementation (PHP 8.3 only) is archived verbatim under `OLD/`.

## Versions

The PHP versions built are **resolved live from the [sury](https://packages.sury.org/php/)
repo** for the current Debian stable codename — every `php<maj>.<min>` sury ships
at or above `MIN_PHP` (default `8.3`). New minor versions are picked up
automatically; a version that sury drops stops building. Override the floor with
the `MIN_PHP` repo variable or the `workflow_dispatch` `min_php` input.

> Note: a version (or one of its extensions) that sury has not published yet will
> fail its build; `fail-fast: false` keeps the other versions publishing.

## Usage

```
docker run --rm -p 80:80 -p 443:443 crbrdocker/apache-php:8.3
```

Debian-based, tuned for a **dev** box (low process/concurrency limits). Two
vhosts are created:

- a **default** vhost → `/srv/www/default/public`
- a **`vhost_alias`** vhost that creates vhosts on the fly from the hostname →
  `/srv/www/%0/public` (for `*.dev`, `*.test`, `*.local`, `*.docker`).

A self-signed SSL certificate covering the `vhost_alias` names (signed by our dev
CA) is installed at `/etc/apache2/ssl/dev.crt` / `dev.key`. Override `/srv/www`
and/or `/etc/apache2/sites-enabled` as needed.

Baked-in environment (in `/etc/environment`): `TZ=Europe/Paris`,
`ENVIRONMENT=dev`, `PLATFORM=dev`, `PLATFORM_URL=dev.`,
`LIB_INCLUDE_PATH=/srv/www/lib/clean`,
`LEGACY_LIB_INCLUDE_PATH=/srv/www/lib/legacy`. PHP is set with
`variables_order=EGPCS`, `date.timezone=Europe/Paris`, `expose_php=Off`,
`post_max_size=80M`, `upload_max_filesize=20M`.

> TODO (carried from the old README): env vars to override the whole config at
> run time.

## How it is built

Everything is driven by `.github/workflows/build.yml`:

1. **resolve** — read the stable codename + the sury PHP version list (≥ `MIN_PHP`);
   lowercase the registry owner.
2. **gate** — `need_rebuild.sh` per version; keep only the ones that changed.
3. **build** — matrix `version × {amd64→ubuntu-24.04, arm64→ubuntu-24.04-arm}`,
   **native, no QEMU**; `docker buildx build` (with `PHP_VERSION` build-arg) pushes
   an OCI `:<ver>-<arch>` image (provenance + SBOM) to both registries.
4. **manifest** — merge the per-arch tags into `:<ver>`.
5. **cleanup** — prune untagged GHCR versions.

Triggers: any push to `main`, weekly `cron 26 4 * * 2`, or manual *Run workflow*
(optional `min_php`).

`install-php.sh` is copied into the image and run once at build time; it takes the
target version from `$PHP_VERSION` and derives the sury repo codename from the base
image's `/etc/os-release`, so the one script serves every version/codename.

### Rebuild gate

`need_rebuild.sh <image-ref> [vcs-ref] [base-image]` prints `REBUILD=true|false`.
It rebuilds when the published image is missing, its
`org.opencontainers.image.revision` label ≠ HEAD, the base `:stable` digest it
was built on has changed, or a simulated `dist-upgrade` shows pending updates.

## Registries & secrets

- GHCR uses the built-in `GITHUB_TOKEN` (needs `packages: write`) — no secret.
- Docker Hub is conditional on secrets `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN`;
  namespace is repo/org var `DOCKERHUB_NAMESPACE` (falls back to the username).
  Absent creds → GHCR-only.
