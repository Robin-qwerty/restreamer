# AGENTS.md

Guide for AI agents (and humans) working on this repository.

## What this repo is

This is the **Docker bundle** for Restreamer 2.x. It contains no application source code.
The actual software lives in other repositories and is pulled in as prebuilt images:

| Component | Upstream repo | Image used |
|-----------|---------------|------------|
| UI (React) | https://github.com/datarhei/restreamer-ui | `datarhei/restreamer-ui:<ver>` |
| Core (Go API, process manager, RTMP/SRT/HLS server) | https://github.com/datarhei/core | `datarhei/base:core<ver>-<os>` |
| FFmpeg runtime (final base layer) | https://github.com/datarhei/ffmpeg | `datarhei/base:ffmpeg<ver>-<variant>-<os>` |

So "updating dependencies" here means bumping image tags and GitHub Actions versions, not npm/go modules.
Code-level changes (UI features, API behaviour) must be made in the upstream repos (or your forks of them)
and then referenced here via build args.

## Layout

- `Dockerfile` – multi-stage build: copies `/core` from the core image and `/ui/build` from the UI image
  into the FFmpeg image. Build args: `RESTREAMER_UI_IMAGE`, `CORE_IMAGE`, `FFMPEG_IMAGE`.
- `run.sh` – container entrypoint (`/core/bin/run.sh`): runs `bin/import` (v1 → v2 DB migration),
  `bin/ffmigrate` (FFmpeg parameter migration), seeds `ui-root/index.html` into the data dir, then execs `bin/core`.
- `ui-root/` – placeholder landing page served from `/core/data` when no player site exists.
- `.github/workflows/build_bundle.yaml` – release images (manual / `workflow_call`); reads versions from
  the UI `package.json` and core `app/version.go`. Matrix: default, `rpi-`, `vaapi-`, `cuda-`.
- `.github/workflows/build_bundle_dev.yaml` – nightly `*-dev` images.
  Both run on `self-hosted` runners and push to Docker Hub `datarhei/restreamer` — change the image name/secrets in a fork.
- `CHANGELOG.md` – release notes (also copied into the UI at build time from upstream `2.x`).
- `_BUNDLE_OF`, `_RESTREAMER-UI+CORE` – empty marker files.

## Runtime facts

- Ports: `8080` HTTP (UI at `/ui`, API at `/api`), `8181` HTTPS, `1935` RTMP, `1936` RTMPS, `6000/udp` SRT.
- Volumes: `/core/config` (config.json + DB), `/core/data` (HLS segments, player site).
- Env: `CORE_CONFIGFILE`, `CORE_DB_DIR`, `CORE_ROUTER_UI_PATH`, `CORE_STORAGE_DISK_DIR`; any core
  config key can be overridden with `CORE_*` env vars (see core docs).

## Build & run locally

```sh
docker build -t restreamer:local .
# or pin components:
docker build \
  --build-arg RESTREAMER_UI_IMAGE=datarhei/restreamer-ui:dev \
  --build-arg CORE_IMAGE=datarhei/base:core-dev-alpine3.23 \
  --build-arg FFMPEG_IMAGE=datarhei/base:ffmpeg8.1.2-alpine3.23 \
  -t restreamer:local .

docker run -d --name restreamer -p 8080:8080 -p 8181:8181 -p 1935:1935 -p 1936:1936 -p 6000:6000/udp \
  -v $PWD/config:/core/config -v $PWD/data:/core/data restreamer:local
```

There are no tests or linters; verify changes by building the image and opening http://localhost:8080/ui.

## Conventions

- Keep `run.sh` POSIX `sh` (Alpine/busybox).
- When bumping FFmpeg/core/OS tags, make sure the tag exists on Docker Hub (`datarhei/base`) for every
  platform in the matrix, and keep core and FFmpeg on the same OS (alpine vs ubuntu).
