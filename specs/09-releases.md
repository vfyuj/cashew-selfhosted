# Releases

**Status:** implemented 2026-08-11, and exercised since — every release from `v1.0.0-beta.21` through `v1.2.1` has shipped through it. The four signing secrets are configured, releases carry a signed APK (~86 MB), and the GHCR package is public: an unauthenticated manifest fetch for `ghcr.io/vfyuj/cashew-selfhosted:1.2.1` returns 200.

Not every version becomes a tag. `1.0.2` and `1.1.1` were both developed and left untagged, and the next release simply carried their changelog sections alongside its own — which is what the changelog's "every section newer than the version you last launched" rule already does, so nothing special is needed.

## Why this exists

`07-versioning.md` covers how a build is *numbered*. This covers how one is *published*: a signed Android APK and a container image the deployment target can actually pull.

Before this, neither existed. `build-apk.yml` produced a debug APK as a 30-day CI artifact, and the container image was never published anywhere — `DEPLOYMENT.md` told the operator to run `docker buildx build --push` by hand from a laptop, because a home server short on memory cannot build the image itself (`flutter build web` wants 3–4 GB of RAM). Both gaps had the same shape: the artifact people install was produced ad hoc, by hand, from an unrecorded commit.

## What a release is

A git tag `v<version>`, matching `version:` in `app/pubspec.yaml` with the `+build` suffix dropped. Pushing it runs `.github/workflows/release.yml`, which produces:

| Artifact | Where |
|---|---|
| `cashew-selfhosted-<version>.apk`, signed with the release key | GitHub Release asset |
| `ghcr.io/vfyuj/cashew-selfhosted:<version>` and `:latest`, linux/amd64 + linux/arm64 | GHCR |

Nothing else publishes. Pushes to `main` still only run `ci.yml` and `build-apk.yml`, which is deliberate: publishing is a decision, not a side effect of merging.

```bash
git tag v1.0.0-beta.22 && git push origin v1.0.0-beta.22
```

## The release-build fix

`flutter build apk --release` used to fail outright while debug builds passed. The cause, and the reason it took a toolchain upgrade rather than a flag:

`sqlite3_flutter_libs 0.5.42` declares `compileSdk = 35`. Android 15's `android.jar` stores its resource table in a form the aapt2 bundled with AGP 7.x cannot read:

```
aapt2 E LoadedArsc.cpp:94] RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data.
Failed to load resources table in APK '.../platforms/android-35/android.jar'.
```

This surfaced only in release builds because it happens in `verifyReleaseResources`, a release-only task. So the fix was AGP 7.3.1 → **8.7.3** (the version `sqlite3_flutter_libs` itself builds against), Gradle 7.5 → **8.9**, `compileSdk` 34 → **35**. AGP 8 then forced three follow-on changes:

1. **Namespaces.** AGP 8 ignores the `package` attribute in `AndroidManifest.xml`. Removed from all three of the app's manifests and replaced with `namespace` in `app/android/app/build.gradle`.
2. **Third-party plugins without a namespace.** Two of 21. `flutter_charset_detector` was bumped `^1.0.2` → `^2.1.0` (first release with one; the app calls only `CharsetDetector.autoDecode`, unchanged across the major). `system_theme` **cannot** be bumped — 3.2.0 has the namespace but pulls `system_theme_web >=0.0.3`, which needs `web ^1.0.0` while Flutter 3.19.6 pins `web 0.5.1`. Its namespace is injected from the root `build.gradle` instead, and that hack should be deleted whenever the Flutter SDK moves.
3. **JVM target alignment.** Kotlin 1.9 targets whatever JDK runs Gradle (17); AGP leaves Java at 1.8 in modules that don't say otherwise; AGP 8 hard-fails on the mismatch where 7.x tolerated it. No single value works — `share_plus` compiles Java at 17, `flutter_charset_detector` at 1.8 — so each module's Kotlin target is derived from that same module's Java target.

Both root-`build.gradle` hooks run from `gradle.beforeProject`, not `subprojects { afterEvaluate { … } }`. The existing `evaluationDependsOn(':app')` evaluates the plugin projects part-way through the `subprojects` iteration, so a hook registered there arrives too late and Gradle fails with *"Cannot run Project.afterEvaluate(Closure) when the project is already evaluated"*. The JVM-target value is read inside `configureEach` rather than `afterEvaluate` for a related reason: AGP finalizes `compileOptions` after our `afterEvaluate` would run (*"targetCompatibility is not yet finalized"*).

Verified locally: `flutter build apk --release` succeeds, producing an ~83 MB universal APK.

### Two things the upgrade broke that only showed up later

**Heap.** `org.gradle.jvmargs` was `-Xmx1536M`, inherited from the upstream template. Under AGP 8 the Jetifier transform on the *debug* Flutter engine jar exceeds it and dies with `Java heap space`. Release builds are unaffected, because the release engine jar is smaller — so a local `--release` build passed while CI, which builds debug, failed. Raised to `-Xmx4G`. Turning off `android.enableJetifier` would remove the transform altogether and is probably safe on an all-AndroidX dependency set, but that changes how every dependency is processed and was not worth bundling into a release change.

**JDK.** AGP 8.7.3 cannot parse a Java version it predates, and fails with the version number as the entire error message:

```
Failed to apply plugin class 'FlutterPlugin'.
   > 25.0.2
```

Both workflows now pin JDK 17 with `actions/setup-java`, rather than trusting the runner default. Locally the trap is worse: **Flutter prefers the JDK bundled with Android Studio over `JAVA_HOME`**, so exporting `JAVA_HOME` does nothing. Point it at a supported JDK explicitly:

```bash
flutter config --jdk-dir=/opt/homebrew/opt/openjdk@17
```

A running Gradle daemon keeps the JVM it started with, so this can lie dormant until something restarts the daemon.

## Signing

`app/android/app/build.gradle` reads `app/android/key.properties` when present and **falls back to the Android debug key when it isn't**. That fallback is why the release workflow refuses to run without the four signing secrets, and why it re-verifies the finished APK and fails on `CN=Android Debug`. A debug-signed release looks completely normal and installs fine — the damage only shows up at the *next* release, when Android refuses to install a differently-signed APK over it.

| Secret | Contents |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the `.jks` file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias |

**The keystore is unrecoverable and permanent.** Lose it and every existing install has to be uninstalled — with its local data — before a new build can be installed, because the signature no longer matches. Back it up somewhere that is not this repository. `key.properties` and `keystore.jks` are gitignored; the workflow writes both on the runner and deletes them in an `always()` step.

Generate one with:

```bash
keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cashew
```

## The image

Multi-arch, `linux/amd64` + `linux/arm64`, so the image runs wherever the server happens to be without anything being compiled on it. Publishing both costs one extra parallel job and removes a whole class of "wrong architecture" problem; drop one if it stops earning that.

Each architecture is built on a runner of that architecture (`ubuntu-latest` and `ubuntu-24.04-arm`, free for public repositories), pushed untagged by digest, and the two digests are then assembled into a single tagged manifest list. Nothing is emulated.

The obvious alternative — one runner, QEMU, `platforms: linux/amd64,linux/arm64` — was rejected because it emulates a `dart2js` compile, which is pathologically slow. The usual fix for *that* is to pin the arch-neutral web stage with `FROM --platform=$BUILDPLATFORM`, and this was tried and reverted: `$BUILDPLATFORM` is a BuildKit variable, and Docker's legacy builder fails to parse the line at all —

```
failed to parse platform : "" is an invalid OS component
```

— which would break `docker compose up --build` on any host whose Docker lacks buildx. That command is the operator's entire deploy loop, so the `Dockerfile` stays portable and the workflow carries the complexity instead.

## Non-goals

- **No F-Droid or Play Store listing.** Sideloading is the distribution model; a pre-release version string isn't a valid `CFBundleShortVersionString` anyway (`07-versioning.md`).
- **No in-app update check.** Unchanged from `07-versioning.md` — the app never phones home.
- **No per-ABI APK splits.** One universal APK is larger but is one file that works on any phone, which matters more for sideloading to a household than the download size does.
- **No release branches.** Tags point at commits on `main`.

## Acceptance criteria

- [x] `flutter build apk --release` succeeds locally.
- [x] `flutter analyze` reports no errors and `flutter test` passes after the plugin upgrades.
- [x] `flutter build web` still succeeds, so the container image is unaffected.
- [x] Owner: generate the keystore, back it up, add the four secrets. Confirmed 2026-08-12 — the keystore is stored and backed up, and all four secrets are set.
- [x] Owner: push a tag and confirm the workflow produces a Release with an APK plus a `:<version>` image on GHCR.
- [x] Owner: confirm the published APK installs on a phone and works. Confirmed 2026-08-12.
- [x] Owner: make the GHCR package public, then confirm `docker pull` works without credentials. (Public — an unauthenticated manifest fetch returns 200.)
