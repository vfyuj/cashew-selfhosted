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

Confirm locally on that machine:
```
curl localhost:8080/health   # -> {"status":"ok"}
curl -I localhost:8080/      # -> HTTP/1.1 200 OK (the app UI)
```

## 2. Create your account(s)

No public self-registration (see specs/03-stage-1-kill-google.md) — provision each person via the CLI baked into the image:

```
docker compose exec app /app/bin/create_user your@email.tld
```

This prints a one-time temporary password. There's no password-reset flow — re-run the same command to issue a new temporary password if you lose it. Repeat once per person (e.g. yourself, then your spouse).

## 3. Pick a subdomain

Placeholder used below: `cashew.yourdomain.tld` — replace with your actual domain and whatever subdomain you prefer (e.g. `budget.`, `money.`, matching however Nextcloud/Immich are named, like `nextcloud.yourdomain.tld`).

Add a DNS record (A or CNAME, same pattern as your existing subdomains) pointing `cashew.yourdomain.tld` at your home server's public IP / dynamic DNS host — however you already do this for Nextcloud/Immich.

## 4. Nginx Proxy Manager: one Proxy Host, no path splitting

Since one container serves everything, this is a plain single-target proxy host — no Custom Locations needed (unlike a typical multi-container app).

Use the home server's **LAN IP** (e.g. `192.168.1.x`) as the forward target — not the Docker Compose service name (`app`). That name only resolves *inside this project's own* Docker network; NPM is almost certainly its own separate Compose stack (or a host install) with no reason to be joined to this one. Going through the LAN IP + published port (`8080`) avoids touching NPM's Docker setup at all.

In the NPM web UI → **Proxy Hosts** → **Add Proxy Host**:

**Details tab**:
- **Domain Names**: `cashew.yourdomain.tld`
- **Scheme**: `http`
- **Forward Hostname / IP**: your home server's LAN IP
- **Forward Port**: `8080`
- **Cache Assets**: off (fine either way, but the app already sets its own no-cache headers on the files that need it — see `server/lib/src/web_handler.dart`)
- **Block Common Exploits**: on
- **Websockets Support**: off for now (not needed until Stage 2)

Under the **SSL** tab:
- Request a new **Let's Encrypt** certificate for `cashew.yourdomain.tld`
- Enable **Force SSL**
- Enable **HTTP/2 Support**

Save.

## 5. Verify from outside the home network

From a phone on cellular data (not home wifi):

```
curl https://cashew.yourdomain.tld/health
```

Expected: `{"status":"ok"}` with a valid HTTPS certificate (no browser warning). Then open `https://cashew.yourdomain.tld/` in an actual browser tab — you should see the app UI.

## 6. Sign in from the app

Open `https://cashew.yourdomain.tld/` (this is now the app itself — on iPhone, add it to the home screen here for the PWA experience described in `specs/00-overview.md`). In the sign-in screen (Backup page → sign in):
- There's no server URL field on web — the app already knows it's talking to its own origin.
- **Email** / **Password**: from step 2. There's no in-app password-change flow yet (see specs/03-stage-1-kill-google.md) — you keep using the temporary password `create_user` printed, or re-run it to issue a new one.

On the native mobile app (a generic build that isn't tied to any one server), you'll still enter `https://cashew.yourdomain.tld` manually in that same server URL field the first time.

## 7. Record what you used

Once done, note here (or wherever you track infra) what subdomain and LAN IP you actually used, since NPM's forward target (step 4) references that IP directly and will need updating if it ever changes (e.g. switch it to a Docker network alias, or a static DHCP reservation, to avoid that).
