# Stage 0 — Foundations

No user-visible behavior change. Goal: every tool and skeleton needed for Stage 1 exists and is proven reachable.

## Status (last updated 2026-08-08)

- [x] **Task 1 — dev environment.** Flutter pinned to 3.19.6 (only version compatible with upstream's `intl`/`share_plus` lock combo — newer stable Flutter breaks `pub get` or crashes dart2js on `share_plus` web). Android SDK 34/36 + build-tools + JDK 17 installed via Homebrew, all without sudo. `flutter build apk` and `flutter build web` both verified against pristine `upstream/`.
- [x] Task 2a — placeholder name/id: pubspec name `cashew_selfhosted`, Android `applicationId` `com.selfhosted.cashew`, label "Cashew Selfhosted", web manifest/title updated. Verified via `aapt dump badging` that the built APK has a distinct package id from upstream's `com.budget.tracker_app`.
  - [ ] Task 2b — new icon assets (still using upstream's icon; blocked on choosing a real app name/identity).
- [x] **Task 3 — repo restructure.** `/app` created (copy of `upstream/budget`, all `package:budget/` imports repointed to `package:cashew_selfhosted/`). `upstream/` verified untouched. `/server` created (task 4).
- [x] **Task 4 — backend skeleton.** Dart `shelf` service in `/server`, `GET /health`, Dockerfile (multi-stage, `dart compile exe`) + root `docker-compose.yml`. Verified with `docker compose up --build` (via Homebrew `colima`) + `curl localhost:8080/health` → 200.
- [x] Task 4b — web UI serving, now folded into the single server container. Originally shipped as a second container (`app/Dockerfile` + nginx, port 8081) behind an NPM path-split, because task 4 only covered the API and nothing served `/`. Simplified 2026-08-08: for a one-instance, two-user home deployment the two-container split (CORS middleware, nginx config, NPM Custom Locations) was complexity with no real payoff, so the Dart server now serves the compiled Flutter web build directly (`server/lib/src/web_handler.dart`, `shelf_static`, SPA fallback to `index.html`) from the same port as the API. One container, one origin, no CORS needed anywhere. `app/Dockerfile`/`app/nginx.conf` removed; build logic moved into the root `/Dockerfile` (two build stages — Flutter web, Dart compile — one final image). Verified locally: `flutter build web --release` + `dart run bin/server.dart` with `WEB_DIR` pointed at the build output — `curl localhost:<port>/` → 200 (no-cache `index.html`), an unknown path falls back to `index.html` (SPA routing), a real static asset caches normally, and `/auth/login`, `/sync/files` still hit the API (401, not swallowed by the web fallback).
- [ ] **Task 5 — home server deployment.** Needs the operator's physical server; not reachable from this environment. Runbook written at `/DEPLOYMENT.md` — now a single container behind **one** plain NPM proxy host (no Custom Locations needed, since everything is on one port). This is the one Stage 0 task requiring manual follow-through on the operator's own hardware.

## Tasks

### 1. Dev environment
- Install Flutter SDK (stable channel), confirm web support enabled (`flutter config --enable-web`, default in recent Flutter).
- Install Android SDK / platform tools sufficient for `flutter build apk` (adb already present via Homebrew; still need full build-tools + a JDK).
- Xcode is **not required** — native iOS is out of scope per `00-overview.md`.
- **Done when**: `flutter doctor` shows no blocking issues for Android + web targets; `flutter build apk` and `flutter build web` both succeed against the untouched upstream source in `upstream/`.

### 2. Fork identity
- Choose a new app name (distinct from "Cashew") and new icon assets.
- Change Android `applicationId` so the fork can install alongside stock Cashew without collision.
- Update `pubspec.yaml` name/description.
- **Done when**: a renamed build installs on a device that already has official Cashew installed, without conflict, and shows the new name/icon.

### 3. Repo restructure
Target layout:
```
/app      — the Flutter fork (moved/renamed from upstream's budget/)
/server   — new Dart backend (new, empty until task 4)
/specs    — this directory
/upstream — kept as-is, read-only reference
```
- **Done when**: repo builds from this layout; `upstream/` is untouched and still diffable against the fork for porting future upstream fixes.

### 4. Backend skeleton
- New Dart service (`shelf` or `dart_frog`) in `/server` with a single route: `GET /health` → `200 {"status":"ok"}`.
- Dockerfile + docker-compose service definition.
- No database, no auth, no business logic yet — this task is purely "prove the container runs and is reachable."
- **Done when**: `docker compose up` runs the container locally and `curl localhost:<port>/health` returns 200.

### 4b. Web UI serving
- The same `/server` Dart binary builds the Flutter web app from source (as a separate Docker build stage) and serves the compiled output directly alongside the API, on the same port. Rebuilds from source on every `docker compose up --build` — no manual "build locally, copy files to server" step to remember on redeploys.
- One container/one image on purpose: for a one-instance, two-user home deployment, the API and the web UI don't need independent rebuild/redeploy or separate scaling, and a shared origin means the browser never makes a cross-origin request between them — no CORS, no reverse-proxy path routing to configure (see task 5).
- **Done when**: `docker compose up --build` runs the container locally; `curl localhost:8080/` returns 200 with the app's `index.html`, alongside `curl localhost:8080/health` → 200.

### 5. Home server deployment
- Reverse proxy entry + HTTPS on a new subdomain of the owner's existing domain, in front of the single container (task 4, task 4b) — a plain single-target proxy host, since the API and web UI share one port and there's nothing to split by path. (Confirm which reverse proxy is already in use for Nextcloud/Immich before writing config — do not assume.)
- **Done when**: `curl https://<subdomain>/health` returns 200 from outside the home network (e.g., from a phone on cellular data), and opening `https://<subdomain>/` in a browser shows the app UI (not a 404/"Route not found").

## Non-goals for this stage

No auth, no data endpoints, no changes to the app's sign-in/sync/backup code. Stage 0 only proves the pipes exist.

## Open questions to resolve before/during execution

- Which reverse proxy fronts the home server today (Traefik / Nginx Proxy Manager / Caddy / Cloudflare Tunnel / other)?
- What is the new app name?
- Subdomain naming convention to use.
