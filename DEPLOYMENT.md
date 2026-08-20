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

### If the server is short on memory: pull a published image instead of building

`flutter build web --release` wants roughly 3–4 GB of RAM. On a host with less it either thrashes swap for a very long time or gets OOM-killed part-way through. This is a *build*-time problem only — the compiled server idles in well under 100 MB, which is why `docker-compose.yml` caps the container at 512 MB.

So don't build there. Every tagged release publishes ready images for amd64 and arm64 (see `specs/09-releases.md`), and `deploy/docker-compose.yml` in this repository is a ready-made compose file that pulls one instead of building. That template is what `README.md` walks new installs through: download it plus `deploy/.env.example` into an empty folder, `cp .env.example .env`, and

```bash
docker compose up -d
```

Version, host port, data location and the two behaviour flags all come from `.env`, so there is nothing to edit in the compose file itself. Pin `CASHEW_VERSION` to an exact release if you'd rather choose when to move; `latest` follows every release at the next `docker compose pull`. `docker pull` needs no credentials as long as the GHCR package is public — packages start **private**, so make it public once, under the repository's Packages page, or the pull gets a 401.

**Note the two compose files keep data in different places.** The one at the repository root uses a named volume (`server-data`), which is where an existing deployment's database already is; `deploy/docker-compose.yml` bind-mounts `./data` next to itself, so the folder *is* the instance. Switching an existing deployment from one to the other does not move the data — it will come up empty and look like everything is gone. To actually migrate, copy it out of the volume first:

```bash
docker compose down
docker run --rm -v cashew-selfhosted_server-data:/from -v "$PWD/data":/to alpine sh -c 'cp -a /from/. /to/'
```

Check the volume's real name with `docker volume ls` first — Compose prefixes it with the project directory name.

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

## 3. After upgrading past 1.3.x: the old `sync/` folder

Devices used to sync by trading whole SQLite files, one per device, kept under `sync/<datasetId>/` in
the data directory. That mechanism was removed — sync is a row-level change feed now
(`specs/04-stage-2-instant-sync.md`), and nothing reads or writes those files any more.

They are not deleted for you, because deleting data on upgrade is not a thing this project does
quietly. Once every device has updated and you have confirmed sync works, the folder can go:

```bash
docker compose exec app sh -c 'du -sh /data/sync && rm -rf /data/sync'
```

Leaving it costs only disk. Deleting your local database is a different matter, so note what this
does *not* touch: `backup/`, `attachments/` and `db.sqlite` are all untouched, and your devices' own
data was never in here in the first place.
