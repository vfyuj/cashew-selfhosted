# Home server deployment (Stage 0, task 5)

This step can't be done from this dev environment — it requires access to your actual home server, router/DNS, and Nginx Proxy Manager (NPM) instance. Follow this runbook there.

## 1. Get the container running on the host

`docker compose` here builds and runs **one** container — see `docker-compose.yml` and `/Dockerfile`: a Dart server that serves both the API (`/auth`, `/sync`, `/backup`, `/health`) and the compiled Flutter web UI (everything else) on port 8080. One container, one port — the browser only ever talks to one origin, so there's no CORS and nothing to split by path at the proxy.

On the home server (wherever Nextcloud/Immich already run):

```
git clone https://github.com/vfyuj/cashew-selfhosted.git
cd cashew-selfhosted
docker compose up --build -d
```

The build compiles the Flutter web app from source inside Docker (needs to download the Flutter SDK image the first time), so the first `--build` will take noticeably longer than a Dart-only build — that's expected, and it also means any redeploy rebuilds the web UI even if you only changed server code. Re-running `docker compose up --build -d` after a `git pull` is the entire redeploy process; there's no separate manual build-and-copy step.

### If the home server is a Raspberry Pi: build somewhere else and push a ready docker file

`flutter build web --release` wants roughly 3–4 GB of RAM. On a Pi 4 that either thrashes swap for a very long time or gets OOM-killed part-way through, and on a Pi with less than 4 GB it will not finish at all. This is a *build*-time problem only — the compiled server idles in well under 100 MB, which is why `docker-compose.yml` caps the container at 512 MB.

So build the image on your laptop and push it, rather than building on the Pi:

```bash
docker buildx build --platform linux/arm64 -t ghcr.io/vfyuj/cashew-selfhosted:latest --push .
```

Then on the Pi, point `docker-compose.yml` at that image instead of building — swap `build: .` for `image: ghcr.io/vfyuj/cashew-selfhosted:latest` — and redeploy with:

```bash
docker compose pull && docker compose up -d
```

Check `/health` afterwards exactly as above; the version number is still how you confirm the new build actually landed.

Confirm locally on that machine:
```
curl localhost:8080/health   # -> {"status":"ok","version":"1.0.0-beta.12"}
curl -I localhost:8080/      # -> HTTP/1.1 200 OK (the app UI)
```

**Confirming a redeploy actually landed.** The version in `/health` is read out of the web build being served, so it is the same number the app shows in its sidebar (bottom row, where "About" used to be). After a `git pull` + rebuild, that number should have gone up; if it hasn't, the rebuild didn't take, and if `curl` shows a higher number than your browser does, the browser is holding a cached build — hard-refresh it. See `specs/07-versioning.md`.

## 2. Create the administrator account — do this promptly

The first person to open a fresh instance creates its administrator account, the same way Nextcloud and Immich work (see `specs/05-accounts-and-admin.md`). Setup then closes permanently, and that administrator adds everyone else from inside the app — there's no CLI step in the normal path any more.

**This means there is a window, between the container starting and you registering, in which anyone who can reach the server could claim the administrator account.** That's an accepted trade-off, but it makes the order of operations matter: bring the container up and register **before** you point public DNS at it, or immediately after.

Check the state at any time:

```bash
curl localhost:8080/auth/setup-state
```

`{"needsSetup":true}` means nobody has registered yet. If it says `false` and you didn't create that account, someone else did — wipe the data volume (`docker compose down -v`) and start again.

To register, open the app (locally at `http://localhost:8080/`, or via your domain once step 4 is done) and follow the **Set up this server** screen.

### Adding the rest of the household

Once signed in as the administrator: **Account → Manage users → Add user**. It generates a temporary password, shown once — copy it and pass it on. They sign in with it and can change it under **Account → Change password**.

### Rescue path

If the only administrator loses their password and no other administrator can reset it, the CLI is still in the image:

```bash
docker compose exec app /app/bin/create_user your@email.tld
```

It creates the account if the email is new, or issues a fresh temporary password if it already exists, and prints it either way. `--admin` grants administrator; the very first account created always gets it automatically.
