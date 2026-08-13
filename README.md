<h1 align="center"><b>Cashew Selfhosted</b></h1>

<div align="center">
  <img alt="Cashew Selfhosted icon" src="app/assets/icon/icon.png" width="140px">
</div>

<p align="center">
  <b>Your budget, on your server.</b><br>
  A fork of <a href="https://github.com/jameskokoska/Cashew">Cashew</a> that runs entirely on hardware you own.
</p>

<p align="center">
  <a href="https://github.com/vfyuj/cashew-selfhosted/releases/latest">Releases</a> ·
  <a href="DEPLOYMENT.md">Deployment runbook</a> ·
  <a href="docs/">How it works</a> ·
  <a href="specs/">Design specs</a>
</p>

---

Cashew Selfhosted is the same budgeting app as [Cashew](https://github.com/jameskokoska/Cashew) — a
Flutter app with a local SQLite database, custom budgets, goals, multiple accounts and currencies —
but untied from Google. Sign-in, syncing between devices and backups are handled by a small Dart
server you run yourself, in one container, on one port.

## ⚠ How this was built

This fork was written with the help of Claude, Anthropic's AI coding agent. I'm not a professional
developer, and I can't guarantee the quality or security of the code — please treat it accordingly
before trusting it with anything you'd hate to lose. Keep backups.

If you *are* a professional developer, I'd genuinely welcome an audit, a second opinion, or any
help — especially on the server, the sync logic and the auth code. The quickest way in is
[docs/server/api.md](docs/server/api.md), which lists every endpoint with its auth level and the data
it can reach; [docs/](docs/) covers the rest of the moving parts.

<img alt="Cashew Selfhosted home page" src="https://github.com/user-attachments/assets/c5a4e7c2-41a9-4bdc-8bf8-e8b978117506">

## Why this fork exists

Cashew is built around Google's infrastructure, which imposes certain limitations. I decided to
completely decouple it from Google and implement self-hosted server support. That makes new features
possible, such as independent authentication and quick live synchronization. In the future I plan to
make it an ultimate solution for family finance tracking, by implementing multi-account and
data-sharing support.

## What's different from upstream Cashew

| | Upstream Cashew | Cashew Selfhosted |
|---|---|---|
| Sign-in | Google Sign-In / Firebase Auth | Accounts on your own server |
| Sync | Google Drive, manually triggered | Live row-level sync over your own server |
| Backup | Google Drive | Your server, or Nextcloud/WebDAV |
| Attachments | Google Drive | Your server |
| Receipt scanning | Gmail | Removed ([BL-005](specs/backlog/BL-005-imap-receipt-scanning.md)) |
| Distribution | Play Store / App Store | Docker image, sideloaded APK, PWA |

I've removed Google Sign-In, Firebase, Firestore, `googleapis` and Google Play services from the
dependency list. Outside your own server, the app makes exactly one third-party request: daily
currency exchange rates from a [public rates API](https://github.com/fawazahmed0/exchange-api),
cached locally, only if you use multiple currencies.

### Backwards compatibility support

The app's database layout is deliberately **identical to upstream's**. An original Cashew backup
imports as-is.

## Features

Everything upstream does, minus the Google-backed features in the table above, plus a few things
this fork added.

### 💸 Budgets

- Custom budgets over any period — monthly, weekly, daily, or a one-off range for a trip
- Per-category spending limits, and budgets you add transactions to selectively
- Past budget history, with **per-period amounts**: changing a budget's amount applies from the
  current period onward, so finished periods keep the target they actually had
- Goals for saving and spending, including long-term loans

### 💰 Transactions

- Upcoming, subscription, repeating, borrowed and lent transaction types, each behaving sensibly
- Custom categories and icons; titles that auto-assign a category once you've used them
- Search and filters by date, category, amount and more
- Multi-select by long-press to edit or delete in bulk
- Bill splitter, and attachments stored on your own server

### 💱 Accounts and currencies

- Multiple accounts and currencies, converted automatically at up-to-date rates
- Switch the display account/currency from the home page and everything reconverts instantly

### 📊 Monthly Cash Flow

The Home and Budgets pages show what you expect to come in and what you've planned to spend as two
separate figures. It answers the question budgets are actually for: does this month fit?

<img alt="Planned and Actual Monthly Cash Flow cards" src="https://github.com/user-attachments/assets/405c120f-6424-4d61-861c-c3720f9671c6">

### ☁ Syncing you don't have to think about

Your devices stay constantly synced while online. Edit a transaction on your phone and the laptop
updates while you're watching it. It stays correct when the network doesn't cooperate: every device
keeps working offline and catches up when it can reach the server again.

Backups go to your own server by default, or to Nextcloud/WebDAV if you'd rather.

<img alt="Live sync between devices" src="https://github.com/user-attachments/assets/1cf7125a-11ac-4940-a142-bd150979433a">

### 💿 Automation

- Notifications and reminders for upcoming transactions and budget goals
- CSV import and export
- Automatic transactions parsed from Android notifications, using templates you define
- App links, for creating pre-filled transactions from other apps

## Installing

### Requirements

- **Docker Engine** and **Docker Compose v2** on the machine that will run the server. Compose v2 is
  included with Docker Desktop and with Docker Engine's `docker-compose-plugin`; if
  `docker compose version` prints a version number, you have everything you need.
  - [Install Docker Engine](https://docs.docker.com/engine/install/) — Linux servers
  - [Install Docker Desktop](https://docs.docker.com/desktop/) — macOS, Windows
  - [Install Docker Compose](https://docs.docker.com/compose/install/) — if you installed Engine
    without the plugin
- Roughly 500 MB of disk for the image, plus whatever your data grows to (a few MB for most people).
- `amd64` or `arm64` — both are published, so either works. Nothing is compiled on
  your machine, which is deliberate: building the web UI needs 3–4 GB of RAM and will not finish
  without it, while the server it produces idles under 100 MB.

### Server

Make a folder for the instance and go into it. Everything — the app's database, backups and
attachments — stays inside this one folder, so it's the only thing you ever need to back up or move:

```bash
mkdir -p cashew && cd cashew
```

Download the two templates:

```bash
curl -O https://raw.githubusercontent.com/vfyuj/cashew-selfhosted/main/deploy/docker-compose.yml
curl -O https://raw.githubusercontent.com/vfyuj/cashew-selfhosted/main/deploy/.env.example
```

Copy the example to `.env`. The defaults work as they are, so you can edit it now or leave it —
[`.env.example`](deploy/.env.example) explains every setting, and the ones you're most likely to
want are the port and which version to run:

```bash
cp .env.example .env
```

Start it:

```bash
docker compose up -d
```

That's it — open `http://localhost:8080` (or whichever port you set) and create your administrator
account. To check on it from the command line, `curl localhost:8080/health` returns the running
version.

**Your data is in `./data`, next to the compose file.** Copying that folder copies the entire
instance; there's no hidden state anywhere else. On Linux those files are owned by root, so copying
them takes `sudo`.

To upgrade later, from the same folder:

```bash
docker compose pull && docker compose up -d
```

If you'd rather build from source than pull a published image, clone the repository and use the
`docker-compose.yml` at its root instead — see [DEPLOYMENT.md](DEPLOYMENT.md).

‼️ **The first person to open a fresh instance creates its administrator account.**


### Android

Download the `.apk` from the [latest release](https://github.com/vfyuj/cashew-selfhosted/releases/latest).
You'll need to allow installation from unknown sources. It is not on Google Play.

### iOS and desktop

No native iOS build — open your server's URL in Safari and **Add to Home Screen**. It's a PWA and
runs standalone. Same story on desktop: use the browser, or install it as a PWA.

## License and credit

GPL-3.0 — see [LICENSE](LICENSE).

This is a fork of **[Cashew](https://github.com/jameskokoska/Cashew)** by
[jameskokoska](https://github.com/jameskokoska), which is where essentially all of the app you see
here comes from. Cashew has been developed since September 2021 and is available on the [App
Store](https://apps.apple.com/us/app/cashew-expense-budget-tracker/id6463662930), [Google
Play](https://play.google.com/store/apps/details?id=com.budget.tracker_app) and as a [web
app](https://budget-track.web.app/) — if you don't specifically need self-hosting, use the original.

The translations also come from upstream, and are the work of Cashew's community translators. This
fork now maintains them itself rather than regenerating them from upstream's spreadsheet — what it
has changed, and when, is recorded in
[app/assets/translations/README.md](app/assets/translations/README.md).

This fork is a personal project, built for one household's server and published because GPL-3.0 asks
for the source to stay available. It comes with no promise of support — though see the note at the
top if you'd like to help.
