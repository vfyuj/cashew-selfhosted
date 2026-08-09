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
- **Websockets Support**: **on** — required for live sync's `/sync-stream` endpoint (specs/04-stage-2-instant-sync.md). Sync still works with this off (falls back to a 45s poll), just without the near-instant push.

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

Open `https://cashew.yourdomain.tld/` (this is now the app itself — on iPhone, add it to the home screen here for the PWA experience described in `specs/00-overview.md`). A fresh install shows the setup/sign-in wizard before anything else:
- On web there's no server URL field — the app already knows it's talking to its own origin. If you ever need to override that, it's behind "change server address".
- On the native mobile app (a generic build not tied to any one server), enter `https://cashew.yourdomain.tld` on the first screen.
- Everyone can change their own name, email and password under **Account**.

**Force SSL matters for password managers.** No browser will offer to save or fill a password over plain `http://`. If you skipped the SSL step, sign-in still works but your password manager will stay silent. Note also that browser *extensions* (1Password, Bitwarden) are unreliable with Flutter web regardless — the browser's own built-in manager, and Android's native autofill, work properly. See `specs/05-accounts-and-admin.md` for the details.

**Nobody is ever forced to sign in.** The wizard always offers "use without an account", and the app is fully usable offline forever if you take it — you can connect a server later from the account page.

## 7. Record what you used

Once done, note here (or wherever you track infra) what subdomain and LAN IP you actually used, since NPM's forward target (step 4) references that IP directly and will need updating if it ever changes (e.g. switch it to a Docker network alias, or a static DHCP reservation, to avoid that).
