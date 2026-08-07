# Home server deployment (Stage 0, task 5)

This step can't be done from this dev environment — it requires access to your actual home server, router/DNS, and Nginx Proxy Manager (NPM) instance. Follow this runbook there.

## 1. Get the server running on the host

On the home server (wherever Nextcloud/Immich already run):

```
git clone https://github.com/vfyuj/cashew-selfhosted.git
cd cashew-selfhosted
docker compose up --build -d
```

Confirm locally on that machine: `curl localhost:8080/health` → `{"status":"ok"}`.

## 2. Create your account(s)

No public self-registration (see specs/03-stage-1-kill-google.md) — provision each person via the CLI baked into the server image:

```
docker compose exec server /app/bin/create_user your@email.tld
```

This prints a one-time temporary password. There's no password-reset flow — re-run the same command to issue a new temporary password if you lose it. Repeat once per person (e.g. yourself, then your spouse).

## 3. Pick a subdomain

Placeholder used below: `cashew.yourdomain.tld` — replace with your actual domain and whatever subdomain you prefer (e.g. `budget.`, `money.`, matching however Nextcloud/Immich are named, like `nextcloud.yourdomain.tld`).

Add a DNS record (A or CNAME, same pattern as your existing subdomains) pointing `cashew.yourdomain.tld` at your home server's public IP / dynamic DNS host — however you already do this for Nextcloud/Immich.

## 4. Nginx Proxy Manager: add a Proxy Host

In the NPM web UI → **Proxy Hosts** → **Add Proxy Host**:

- **Domain Names**: `cashew.yourdomain.tld`
- **Scheme**: `http`
- **Forward Hostname / IP**:
  - If NPM runs as a Docker container on the **same Docker network** as the `server` container, you can use the compose service name `server` as the hostname (add both to a shared external network, or put NPM's compose file on the same default network as this project — simplest: use the host machine's LAN IP instead, see below).
  - Otherwise (NPM elsewhere, e.g. its own container or host install): use the home server's **LAN IP** (e.g. `192.168.1.x`).
- **Forward Port**: `8080`
- **Cache Assets**: off (this is an API, not static assets)
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

Expected: `{"status":"ok"}` with a valid HTTPS certificate (no browser warning).

## 6. Sign in from the app

In the app's sign-in screen (Backup page → sign in), enter:
- **Server URL**: `https://cashew.yourdomain.tld` (your actual subdomain from step 3)
- **Email** / **Password**: from step 2. There's no in-app password-change flow yet (see specs/03-stage-1-kill-google.md) — you keep using the temporary password `create_user` printed, or re-run it to issue a new one.

## 7. Record what you used

Once done, note here (or wherever you track infra) what subdomain and forward IP/port you actually used, since the app's "server URL" field needs this exact URL on every device.
