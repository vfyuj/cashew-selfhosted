# Running the app locally to test a change

One rule fixes almost every "why is this outdated / why can't it reach the server" problem
we've hit before: **always build and run from this one directory** — the repo root you're
reading this file in right now, never a path under `.claude/worktrees/`. An agent session
sometimes creates a separate worktree (a second checkout of a branch, off in
`.claude/worktrees/<name>/`) to work in isolation. That's fine for the agent, but it means a
second, independent copy of the code exists on disk — if you `docker compose up` from *this*
directory while the actual changes are sitting uncommitted in a worktree, you get exactly the
"outdated version" result you saw. If an agent ever leaves work in a worktree, ask it to bring
those changes into this directory before you test.

## 1. Check what you're about to run

```bash
git status
git log -1 --oneline
```

Confirms which branch/commit this directory is on, and whether there are uncommitted changes
(there often are — this fork's workflow leaves agent work uncommitted until you review it).
`docker compose up --build` builds whatever is on disk here, committed or not.

## 2. Start it

```bash
docker compose up --build -d
```

One container, one port: the Dart server serves both the API and the compiled web UI from
`http://localhost:8080`. Same-origin, same as production — this matters because it's *why* the
first-run wizard's "couldn't reach that server" screen goes away: that screen appears only when
the web UI is served without its backend (e.g. a bare `flutter run -d web-server`), which has no
server to reach. `docker compose up` always has one, at the same origin.

The first build compiles the Flutter web app from source inside Docker and takes a few minutes;
rebuilds after a small change are faster because Docker reuses cached layers.

Data persists in a named Docker volume (`server-data`) across restarts and rebuilds, since it's
tied to this directory's project name — as long as you keep using this one directory, you keep
the same data.

## 3. Open it

`http://localhost:8080` in a browser. Fresh data shows the first-run setup wizard; you can register
an account or tap **Use without an account** — everything works fully offline either way (see
`specs/01-local-first-invariant.md`).

## 4. Stop it when done

```bash
docker compose down
```

Stops and removes the container but keeps your data. Add `-v` only if you actually want to wipe
the database and start over (`docker compose down -v`).

## 5. If something seems stuck or stale

Check what's actually running before assuming the code is wrong:

```bash
docker ps -a                 # containers — is an old one still up on 8080, or a stray one on another port?
git worktree list            # any other checkouts of this repo lying around?
lsof -iTCP -sTCP:LISTEN -n -P | grep -E "8080|8765"   # anything else bound to a dev port?
```

A container built from a different directory/branch than the one you're looking at right now is
the most common cause of "this looks outdated." `docker compose down` in whichever directory
started the stale one, then rebuild from here.

## Faster iteration without Docker (frontend only — no backend)

```bash
cd app && flutter run -d chrome
```

Quicker for pure UI iteration, but there is **no server at this origin**, so the setup wizard's
connectivity check will fail — that's expected, not a bug. Tap **Use without an account** to get
past it, or use `docker compose up --build -d` (above) instead when you need the account/sync
flows to actually work.

### `flutter run -d web-server` on a custom port: always pass `--release`

Needed to preview on a port other than whatever `-d chrome` opens (e.g. to avoid clashing with
another instance already running), or to make the page reachable from another device:

```bash
cd app && flutter run -d web-server --web-port=<port> --web-hostname=0.0.0.0 --release
```

**The `--release` is not optional.** Without it, `flutter run -d web-server` starts in debug mode,
which needs the Dart Debug Chrome Extension to finish its JS bootstrap handshake. Neither a plain
browser nor the sandboxed preview browser has that extension installed, so the bootstrap throws an
uncaught promise rejection before Flutter paints a single frame — the page sits on the splash
spinner forever and then goes fully blank, on every port and every hostname. It looks exactly like
the app is broken; it isn't reachability, it's this. `--release` skips the whole
debug/hot-reload/extension chain, so the page loads normally and — with no backend at this origin —
lands on the documented "Couldn't reach that server" screen above, not a blank one.

Also use `--web-hostname=0.0.0.0`, not `--web-hostname=localhost`: on this Flutter/Dart version
`localhost` binds IPv6 loopback only (`[::1]`), which some browsers fail to reach even though the
server is up (they try `127.0.0.1` first and give up). `0.0.0.0` binds every interface, including
IPv4 loopback, and is also what makes the page reachable from another device on the LAN.
