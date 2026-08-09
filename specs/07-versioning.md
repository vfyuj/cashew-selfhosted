# Versioning

**Status:** implemented 2026-08-09.

## Why this exists

The deploy loop is `git pull && docker compose up --build -d`. Before this, nothing on screen changed when a build landed, so there was no way to answer "am I looking at the new version or a cached old one?" without guessing. Browsers cache, service workers cache, and a rebuilt container looks identical to one that failed to rebuild.

So: one version number that identifies a deployment, visible without opening anything, and guaranteed to change on every commit.

Modelled on Immich, which numbers the whole project as a unit and shows the running version in the sidebar. This fork can go further than Immich needs to, because the web UI and the API ship in the same image from the same commit — there is only ever one version in play per deployment.

## The scheme

`app/pubspec.yaml` is the **single source of truth**. Nothing else stores a version number.

```yaml
version: 1.0.0-beta.<n>+<n>
```

- Numbering restarted at `1.0.0-beta.1`. The fork does **not** continue upstream Cashew's 5.x line. The release it was branched from is recorded as `upstreamBaseVersion` in `app/lib/widgets/showChangelog.dart` and shown on the About page.
- The beta counter and the build number are the same number. One counter, nothing to keep in sync.
- Every commit increments it. Betas are cheap and disposable; they mark builds, not releases.
- The counter runs until the first stable release, which is `1.0.0` — see "Reaching 1.0.0" below.

Reaching the runtime is free: `PackageInfo.fromPlatform()` is awaited at the top of `initializeSettings()` (`app/lib/struct/settings.dart`) before any UI builds, and `flutter build web` writes the same value into `version.json` inside the image.

One constraint worth knowing: a pre-release suffix is not a valid iOS `CFBundleShortVersionString` for App Store submission. Irrelevant while this fork ships web and sideloaded APKs, but it would have to change before any TestFlight build.

## Where the version shows up

| Surface | Form | Source |
|---|---|---|
| Navigation sidebar, on the About row | `v1.0.0-beta.12` | `getVersionStringShort()` |
| About page | `v1.0.0-beta.12+12, db-v46` + "Based on Cashew 5.4.3" | `getVersionString()`, `upstreamBaseVersion` |
| `GET /health` | `{"status":"ok","version":"1.0.0-beta.12"}` | `readWebBuildVersion()` |

The sidebar row replaces the word "About" with the version rather than sitting beside it. Tapping it still opens the About page. Collapsed, the row is the ⓘ icon alone, as before.

`/health` reads the version out of the **deployed web build's** `version.json` rather than from a compiled-in constant, so the number `curl` reports is by construction the number the browser will load. They cannot drift. When `WEB_DIR` is unset (API-only local dev) the field is simply absent.

## The bump hook

`.githooks/pre-commit`, enabled once per clone:

```bash
git config core.hooksPath .githooks
```

It increments the counter and stages `app/pubspec.yaml` into the commit being made. It deliberately stands down in four cases:

| Situation | Why |
|---|---|
| Merge, rebase, cherry-pick, revert in progress | These replay existing commits; bumping would conflict, or inflate the counter once per replayed commit |
| The commit already changes the `version:` line | A deliberate manual bump, e.g. cutting `1.0.0` |
| `app/pubspec.yaml` has unstaged changes | `git add` would sweep unrelated edits into the commit. Prints a message and skips |
| Version line missing or non-numeric | Prints a message and skips rather than guessing |

`git commit --no-verify` bypasses it entirely, by design.

**`git commit --amend` bumps again.** With nothing else staged, the index matches HEAD, so there is no version change for the hook to notice, and git offers a pre-commit hook no reliable way to tell an amend from an ordinary commit — every discriminator that looks like one also matches a normal commit following a bumped one. This is accepted rather than worked around: an amended commit really is a different build, and the counter only has to be unique and increasing, not contiguous. Amend freely; the number just moves faster than the commit count.

**Not a validation gate.** The hook never rejects a commit. A stale version number is a much smaller problem than a repo you cannot commit to, and a hook that can block commits is a hook people disable.

Because `core.hooksPath` is per-clone and not carried by `git clone`, a fresh clone gets no bumping until that config is set. That is the known weak point of this approach; the alternative (deriving the version from `git describe` at Docker build time) was rejected because `.dockerignore` excludes `.git/` and it would have meant replacing the deploy command with a wrapper script.

## The changelog

`getChangelogString()` in `app/lib/widgets/showChangelog.dart` holds this fork's changelog, newest section first. Upstream Cashew's changelog was removed when the fork started numbering its own releases; it is still readable verbatim in the read-only clone at `upstream/budget/lib/widgets/showChangelog.dart`.

**Add a section only when a change is worth interrupting someone for.** Most betas get none. A version with no section of its own shows no popup at all — `getChangelogPointsWidgets` only emits entries whose heading is newer than the version the user last launched, and `showChangelog` shows nothing when that list comes back empty. This is what keeps per-commit bumping from producing a popup on every deploy.

Format:
- `    < 1.0.0-beta.14` opens a section and is rendered as its heading.
- Any other non-empty line is a bullet; an empty line is a spacer.
- Four-space indent on every line, which the parser strips.
- Raw English strings, **not** `.tr()` keys. `assets/translations/generated/*.json` is machine-generated from an upstream sheet this fork does not control, so any key added there is lost on regeneration — see `specs/backlog/BL-003-upstream-legacy-translations-and-docs.md`.

`getMajorChanges()` (the highlighted, tappable cards above the bullets) is empty. Upstream's entries were all `.tr()` keys and could not be carried over. It remains as an extension point.

### Version ordering

`parseVersionInt()` maps a version string to a comparable integer with semver ordering: `1.0.0-beta.1 < 1.0.0-beta.2 < 1.0.0 < 1.0.1`. A release outranks every pre-release of the same `major.minor.patch`.

This is load-bearing and silent when wrong in either direction — too permissive and the changelog reappears after every deploy, too strict and it never appears. `app/test/version_ordering_test.dart` pins it, including that every section heading in the changelog actually parses.

One consequence, handled explicitly: an install carried over from upstream Cashew has `lastLoginVersion: "5.4.3"` stored, which outranks every `1.x` this fork will ever ship and would hide the changelog forever. `getChangelogPointsWidgets` resets a stored version that is newer than the running one to zero, which also covers downgrades.

## Reaching 1.0.0

When the fork is ready to call itself stable:

1. Set `version: 1.0.0+<n>` in `app/pubspec.yaml` by hand, keeping the build counter where it is. The hook sees a staged version change and stands down.
2. Add a `< 1.0.0` changelog section — this one earns a popup.
3. Tag the commit `v1.0.0`. There are no tags before this point; betas are build markers, not releases.

After 1.0.0 the hook keeps advancing the build number on every commit (still enough to tell two builds apart) but stops touching the release number. Choosing `1.0.1` vs `1.1.0` is a deliberate act, not a hook's job.

## Non-goals

- **No update checking.** The app never phones home to ask whether a newer version exists. Immich does this against the GitHub releases API; this fork does not, and a self-hosted budget app has no business making outbound requests it does not need.
- **No client/server version mismatch warning.** Both ship in one image from one commit, so they cannot disagree — until a native mobile build talks to a separately-updated server, at which point `/health` already carries what such a check would need.
- **No separate server version.** `server/pubspec.yaml`'s `version: 0.1.0` is vestigial and read by nothing.
- **No `CHANGELOG.md` at the repo root.** `getChangelogString()` is synchronous and called from a widget builder, root `*.md` is excluded by `.dockerignore`, and a second copy would drift. A mirror can be generated later if the repo ever needs a public changelog.

## Acceptance criteria

- [x] The sidebar shows the running version; tapping the row still opens the About page.
- [x] The collapsed sidebar shows the ⓘ icon alone, with no clipped text.
- [x] `parseVersionInt` orders betas, releases and the abandoned 5.x lineage correctly (`app/test/version_ordering_test.dart`).
- [x] `/health` reports the version of the web build actually being served, and still answers when there is no web build (`server/test/api_test.dart`).
- [x] A normal commit bumps the counter and includes `app/pubspec.yaml` in that same commit.
- [x] Merges, rebases and cherry-picks do not bump; a commit that already changes the version line is left alone; a dirty `pubspec.yaml` skips with a message rather than widening the commit.
- [x] `--amend` bumps again — known and accepted, see above.
- [ ] Owner check: redeploy, confirm the sidebar number went up, and confirm the changelog pops once and does not come back.
