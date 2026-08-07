# Home server deployment (Stage 0, task 5)

This step can't be done from this dev environment — it requires access to your actual home server, router/DNS, and Nginx Proxy Manager (NPM) instance. Follow this runbook there.

## 1. Get both containers running on the host

`docker compose` here builds and runs **two** separate containers — see `docker-compose.yml`:
- `server` (port 8080) — the API: auth, sync, backup.
- `web` (port 8081) — the actual app UI, a Flutter web build served by nginx.

They're split so each can be rebuilt/redeployed independently, but you'll put both behind **one** public subdomain in step 4, so there's still only one DNS record and one TLS certificate to manage.

On the home server (wherever Nextcloud/Immich already run):

```
git clone https://github.com/vfyuj/cashew-selfhosted.git
cd cashew-selfhosted
docker compose up --build -d
```

The `web` build compiles the Flutter app from source inside Docker (needs to download the Flutter SDK image the first time), so the first `--build` will take noticeably longer than the API alone — that's expected. Re-running `docker compose up --build -d` after a `git pull` is the entire redeploy process; there's no separate manual build-and-copy step.

Confirm locally on that machine:
```
curl localhost:8080/health   # -> {"status":"ok"}
curl -I localhost:8081/      # -> HTTP/1.1 200 OK
```

## 2. Create your account(s)

No public self-registration (see specs/03-stage-1-kill-google.md) — provision each person via the CLI baked into the server image:

```
docker compose exec server /app/bin/create_user your@email.tld
```

This prints a one-time temporary password. There's no password-reset flow — re-run the same command to issue a new temporary password if you lose it. Repeat once per person (e.g. yourself, then your spouse).

## 3. Pick a subdomain

Placeholder used below: `cashew.yourdomain.tld` — replace with your actual domain and whatever subdomain you prefer (e.g. `budget.`, `money.`, matching however Nextcloud/Immich are named, like `nextcloud.yourdomain.tld`).

Add a DNS record (A or CNAME, same pattern as your existing subdomains) pointing `cashew.yourdomain.tld` at your home server's public IP / dynamic DNS host — however you already do this for Nextcloud/Immich.

## 4. Nginx Proxy Manager: one Proxy Host, split by path

Both containers go behind the **same** proxy host — the API's routes (`/auth`, `/sync`, `/backup`, `/health`) are forwarded to the `server` container, and everything else falls through to the `web` container (the UI). This keeps it to one subdomain and one certificate, and the browser never sees a cross-origin request between the UI and the API.

Use the home server's **LAN IP** (e.g. `192.168.1.x`) as the forward target for both — not the Docker Compose service names (`server`/`web`). Those names only resolve *inside this project's own* Docker network; NPM is almost certainly its own separate Compose stack (or a host install) with no reason to be joined to this one. Going through the LAN IP + published ports (`8080`, `8081`) avoids touching NPM's Docker setup at all, and keeps the two stacks free to be moved/redeployed independently of each other.

In the NPM web UI → **Proxy Hosts** → **Add Proxy Host**:

**Details tab** (this becomes the default `/` location, i.e. the UI):
- **Domain Names**: `cashew.yourdomain.tld`
- **Scheme**: `http`
- **Forward Hostname / IP**: your home server's LAN IP
- **Forward Port**: `8081` (the `web` container)
- **Cache Assets**: off (fine either way, but the app already sets its own no-cache headers on the files that need it — see `app/nginx.conf`)
- **Block Common Exploits**: on
- **Websockets Support**: off for now (not needed until Stage 2)

**Custom Locations tab** — add one entry per API path, each pointing at the `server` container instead:

| Define location | Scheme | Forward Hostname/IP | Forward Port |
|---|---|---|---|
| `/auth` | http | your LAN IP | `8080` |
| `/sync` | http | your LAN IP | `8080` |
| `/backup` | http | your LAN IP | `8080` |
| `/health` | http | your LAN IP | `8080` |

(NPM's location matching is a prefix match, so `/auth` also covers `/auth/login`, `/auth/refresh`, etc.)

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

Expected: `{"status":"ok"}` with a valid HTTPS certificate (no browser warning). Then open `https://cashew.yourdomain.tld/` in an actual browser tab — you should see the app UI, not "Route not found" (that error meant you were hitting the API container directly with no `web` container / Custom Locations in front of it — this step confirms the split is wired up correctly).

## 6. Sign in from the app

Open `https://cashew.yourdomain.tld/` (this is now the app itself — on iPhone, add it to the home screen here for the PWA experience described in `specs/00-overview.md`). In the sign-in screen (Backup page → sign in), enter:
- **Server URL**: `https://cashew.yourdomain.tld` — same domain, since the API is reachable at this same origin via the Custom Locations from step 4.
- **Email** / **Password**: from step 2. There's no in-app password-change flow yet (see specs/03-stage-1-kill-google.md) — you keep using the temporary password `create_user` printed, or re-run it to issue a new one.

## 7. Record what you used

Once done, note here (or wherever you track infra) what subdomain and LAN IP you actually used, since NPM's Custom Locations (step 4) reference that IP directly and will need updating if it ever changes (e.g. switch it to a Docker network alias, or a static DHCP reservation, to avoid that).
