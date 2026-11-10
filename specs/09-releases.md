# Releases

**Status:** implemented 2026-08-11, and exercised since — every release from `v1.0.0-beta.21` through `v1.4.1` has shipped through it. The four signing secrets are configured, releases carry a signed APK (~86 MB), and the GHCR package is public: an unauthenticated manifest fetch for `ghcr.io/vfyuj/cashew-selfhosted:1.4.1` returns 200.

Not every version becomes a tag. `1.0.2`, `1.1.1` and `1.4.0` were all developed and left untagged, and the next release simply carried their changelog sections alongside its own — which is what the changelog's "every section newer than the version you last launched" rule already does, so nothing special is needed.

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
2. **Third-party plugins without a namespace.** Two of 21. `flutter_charset_detector` was bumped `^1.0.2` → `^2.1.0` (first release with one; the app calls only `CharsetDetector.autoDecode`, unchanged across the major). `system_theme` **cannot** be bumped — 3.2.0 has the namespace but pulls `system_theme_web >=0.0.3`, which needs `web ^1.0.0` while the resolved `web` is 0.5.1. Its namespace is injected from the root `build.gradle` instead. This was originally recorded as blocked on the Flutter SDK, to be deleted once it moved; **the 3.44 upgrade disproved that** — `web` is still 0.5.1, now capped by `drift`, `sqlite3`, `share_plus` and `web_socket_channel` (all `web: ^0.5.0`), not by the SDK. Lifting it means moving the drift/sqlite3 stack, which is its own job.
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

## The Flutter 3.44 upgrade

PR #50 moved the Dockerfile's web build to `flutter:3.44.0` for one reason: 3.44 is the first release with
flutter/flutter#182024, which fixes password autofill in iOS 26 Safari. It left `pubspec.yaml` and the three
workflows on the old toolchain, so `flutter pub get` could no longer solve — `easy_localization 3.0.8` pulls
`flutter_localizations`, which in 3.44 pins `intl 0.20.2`, against a pubspec asking for `intl ^0.18.1`. The
Docker build and the **v1.4.4 release both failed**, leaving that tag with no APK and no image.

Going back to 3.19.6 would have been one line, and was rejected: it reintroduces the autofill bug that
v1.4.4's changelog already promises is fixed, in all eight locales.

What the jump actually cost, in the order the builds surfaced it:

1. **Dependency solving.** `intl ^0.20.2`, `carousel_slider ^5.0.0`, `flutter_sticky_header ^0.8.0`. The app
   uses only `CarouselSlider`/`CarouselOptions`, never the `CarouselController` that 5.0 renamed, so no app
   code changed. `pubspec.lock` had to be regenerated — `pub get` alone keeps satisfiable old entries, which
   is how `win32 5.5.0` survived and kept failing on `UnmodifiableUint8ListView`, removed from
   `dart:typed_data`.
2. **Three packages that no longer compile.** `device_preview 1.1.0` used `TextTheme.subtitle2`,
   `headline6`, `ThemeData.backgroundColor` and `toggleableActiveColor`, all removed in the 3.22 deprecation
   wave. It was imported in exactly one file behind `false && kDebugMode`, so it was deleted rather than
   bumped — its 3.0.0 needs Flutter ≥3.47 and would have blocked the next upgrade too. `home_widget` went to
   `^0.9.2` (0.5.0 passed a `size:` to `ViewConfiguration`, a constructor that changed shape).
3. **The v1 Android embedding.** Flutter 3.29 removed `PluginRegistry.Registrar`. Two dependencies still
   declared `registerWith(Registrar)` and so could not compile: the `melWiss/flutter_file_picker` git fork,
   stuck at `file_picker 6.0.1`, and `flutter_timezone 1.0.8`. The fork is gone, replaced by upstream
   `file_picker ^8.0.7` — 8.x rather than the current 13.x because from 13.3.3 it pulls
   `windows_file_picker`, which needs `win32 ^6.3.0`, while `device_info_plus ^10.1.0` caps `win32` below 6.
   `flutter_timezone ^5.1.1` returns a `TimezoneInfo` instead of a nullable `String`; `main.dart` now guards
   the `tz.getLocation` call instead of the argument.
4. **The Gradle toolchain.** 3.44 makes the imperative `apply from: ".../app_plugin_loader.gradle"` a hard
   error, so `settings.gradle` and `app/build.gradle` moved to the declarative `plugins` block and the AGP
   and Kotlin versions moved out of a root `buildscript` classpath into `settings.gradle`. That cascaded:
   Kotlin 1.9.0 → **2.2.20** (3.44 refuses to apply its plugin below 2.0.0), AGP 8.7.3 → **8.11.1** (3.44's
   own `androidx.core 1.18.0` and `androidx.navigationevent 1.0.0` demand ≥8.9.1), Gradle 8.9 → **8.14.3**,
   `compileSdk` 35 → **36** (five bundled plugins require it). `targetSdk` stays at 34 — compiling against
   newer APIs is a separate decision from opting in to new runtime behaviour. The explicit
   `kotlin-stdlib-jdk7` dependency went away with `ext.kotlin_version`; KGP 2.x adds the stdlib itself.
   The root `build.gradle` JVM-target hook now matches tasks by their `kotlinOptions` property rather than
   by the `KotlinCompile` type, which is no longer guaranteed loadable from that script.

5. **A release-only `compileSdk` trap, twice.** Flutter 3.44's androidx dependencies reference
   `android:attr/lStar`, added in API 31. Two plugin modules still declare `compileSdk 30`, and resource
   merging against them fails in `verifyReleaseResources` — a release-only task, so a debug APK built
   cleanly while `flutter build apk --release` died with *"AAPT: error: resource android:attr/lStar not
   found"*. Same shape as the AGP 7 failure this document opens with. `flutter_charset_detector` went
   `^2.1.0` → **`^6.0.0`**, whose Android module is on `compileSdk 35`. `system_theme` cannot be bumped at
   all (see above), so its `compileSdk` is forced from the root `build.gradle` beside the namespace
   injection — but from `project.afterEvaluate`, not from `beforeProject` like the namespace: `beforeProject`
   fires before the plugin's own script, which sets `compileSdk 30` itself and would overwrite the
   assignment. The namespace escapes that only because the plugin never sets one.

The Flutter migrator also rewrites two files on first run. `android.builtInKotlin=false` and
`android.newDsl=false` in `gradle.properties` are kept — they opt out of changes this project hasn't made
yet. Its change of `minSdkVersion 23` to `flutter.minSdkVersion` was reverted: the floor is a
device-support decision, not an SDK default.

**Not verified by any of this.** The old file-picker fork existed to work around upstream issue #1404 — on
Android 14 a `FileType.custom` pick returns "user cancelled" immediately, which is exactly what
`importCSV.dart` does. That thread's reported cause is `android:launchMode="singleInstance"` on
`MainActivity`, which this app still sets. So **CSV import on a real Android phone is the one thing to test
by hand** after this change; if the picker closes instantly, `singleTop` is the next lever, not another fork.
Timezone detection at first launch is worth a glance for the same reason.

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
