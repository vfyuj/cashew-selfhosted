# BL-007 — Fork-owned translations and an in-app editor

**Status:** Implemented 2026-08-12. Not yet acceptance-tested by the owner.

**Origin:** owner request (2026-08-12) — drop the translation pipeline, the last live dependency on
upstream Cashew, and replace it with the ability to fix a translation directly in the app: a search
over English-original / current-translation pairs, editable in place. Closes the open question in
[BL-003](BL-003-upstream-legacy-translations-and-docs.md) §2A.

Overrides are read from `sharedPreferences` before `runApp` and applied entirely on-device — no
network call, no gate on auth, no schema change; translations are a UI-layer asset
(`easy_localization`), unrelated to the 10 Drift tables.

---

## 1. The problem

`app/assets/translations/generate-translations.py` re-downloaded `translations.csv` from a Google
Sheet **upstream owns**, then regenerated every file in `app/assets/translations/generated/`. Running
it would wipe this fork's own strings, so it could never actually be run — which meant:

- 45 of 46 locale files were frozen upstream snapshots, each missing exactly the fork's 109
  self-hosting/onboarding keys, which rendered as English.
- Two keys the fork changed were wrong in every other language: `onboarding-title-2` still said
  "Create a budget" (English said "Set up your accounts"), and `onboarding-info-3` still promised
  Google Drive backups.
- The "help translate" card in the language picker opened `mailto:dapperappdeveloper@gmail.com` —
  **upstream's author's personal email.** Fork users clicking it would have written to a stranger about
  strings that stranger never wrote.
- There was no way to fix a bad translation short of hand-editing JSON and rebuilding.

## 2. What this delivers

The locale files are now this fork's own, maintained by hand or through an in-app editor, with no
pipeline that can silently discard fork-specific edits.

```
Settings → Language → Edit translations
  → search "settings", pick a language, edit the string
  → change applies immediately, no restart
  → Export writes a JSON file of every edit made
  → dart run tool/merge_translation_overrides.dart <file>  promotes it into the repo
```

## 3. The load-bearing decisions

| Decision | Choice | Why |
|---|---|---|
| Which languages ship | **8**: `en, ru, de, es, fr, pt, uk, zh` (down from 46) | The other 38 were upstream snapshots nobody here could correct — a translation nobody maintains is worse than none, since it looks authoritative. Recoverable from git history (`19108a8`) if ever wanted back. |
| Where overrides live | A dedicated `sharedPreferences` key, not `appStateSettings` | `updateSettings()` re-encodes the whole settings blob on every write, and `backupSettings()` copies that blob into Drift where it rides the row-level sync feed. A full locale of overrides is ~67 KB; neither path should carry that for an unrelated toggle flip. |
| Live apply vs. restart-required | **Live**, via one pinned private import | `context.setLocale(context.locale)` is a no-op (guarded in `easy_localization_app.dart`), and `resetLocale()` at the same locale never triggers a rebuild either. The only route is re-injecting into the `Localization` singleton the same way the package's own delegate does. Contained to one file; `easy_localization` is pinned to `3.0.8` because of it. |
| Sync overrides across devices | **No** — export/import file only | Overrides are edits to UI strings, not user data; putting them in the sync feed would mix the two channels for a household that in practice edits translations rarely and on whichever device is at hand. |
| Public contribution tooling (Weblate etc.) | **Not yet** | Format stays flat per-locale JSON specifically so pointing a platform at it later needs no migration — see `app/assets/translations/README.md`. |

## 4. How it works

- **Runtime**: `TranslationOverrideAssetLoader` (`app/lib/struct/translationOverrides.dart`) is
  registered as an `extraAssetLoaders` entry. `easy_localization` merges `[bundleLoader,
  ...extraAssetLoaders]` in order, so overrides win over the shipped file for free, at every one of the
  ~1,800 `.tr()` call sites, with zero call-site changes.
- **Live apply**: `applyTranslationOverridesNow()` rebuilds the primary and fallback translation maps
  from `rootBundle` (cached) merged with the override map, and calls `Localization.load(...)` — the same
  public static the package's own delegate calls on every locale change.
- **Editor**: `app/lib/pages/translationEditorPage.dart`. Its own chrome is raw English, never
  `.tr()`, so a mangled `settings` or `cancel` string can never hide the way back to fixing it — it's
  the tool you'd use to fix a broken translation, so it can't depend on the system it exists to
  repair. (The changelog used to follow this same raw-English rule, for the different reason that its
  translations pipeline was upstream-owned; that blocker is gone and the changelog is `.tr()`-based
  now — see `CLAUDE.md` § Versioning.) Search, three filters (All / Missing here / Edited), a
  placeholder-mismatch warning (`{app}`, `{account}` are the only two used anywhere), and two
  revert-all actions.
- **Entry point**: `TranslationsEditorTile` (`app/lib/struct/settings.dart`) replaces the old
  `TranslationsHelp` mailto card at both call sites (language picker, About page), plus a direct
  settings row.
- **Export/import**: `app/lib/struct/translationOverridesFile.dart`, reusing the existing `saveFile()`
  / `FilePicker` helpers. Import merges (imported wins) rather than replaces, so importing a
  German-only file can't silently drop edits to other languages.
- **Promotion**: `app/tool/merge_translation_overrides.dart`, a plain-Dart CLI (`dart:io` /
  `dart:convert` only, no Flutter toolchain needed — same pattern as `server/bin/create_user.dart`).
  `--self-test` proves the JSON encoder reproduces every shipped file byte-for-byte before the tool is
  trusted to write anything; `--dry-run` reports without writing.
- **Hygiene**: `app/test/translation_keys_test.dart` fails CI if a literal `.tr()` key has no entry in
  `en.json` — the same class of bug this change fixed 5 live instances of
  (`attachment-requires-account`, `create-account`, `currency-label`,
  `currency-label-description`, `remain`). Runs under plain `flutter test`, no workflow change needed.

## 5. Where the code is

| File | Role |
|---|---|
| `app/lib/struct/translationOverrides.dart` | **New.** Override storage, the asset loader, live-apply. |
| `app/lib/struct/translationOverridesFile.dart` | **New.** Export/import file format and I/O. |
| `app/lib/pages/translationEditorPage.dart` | **New.** The editor UI. |
| `app/tool/merge_translation_overrides.dart` | **New.** Repo-side promotion CLI. |
| `app/lib/struct/languageMap.dart` | `supportedLocales` trimmed to 8; `getLocalePath` simplified (also fixed a real bug — see §6). |
| `app/lib/struct/settings.dart` | `TranslationsHelp` → `TranslationsEditorTile`. |
| `app/lib/struct/defaultPreferences.dart` | `attemptToMigrateUnsupportedLocale()` — resets a dropped language to "System" on first launch after the update. |
| `app/assets/translations/generated/*.json` | 41 locale files removed; `ru.json` rewritten from scratch (1,296 keys); 5 keys added to all 7 remaining files; 12 stale Google/onboarding strings fixed across 6 non-English, non-Russian locales. |
| `app/assets/translations/README.md` | **New.** Provenance and GPLv3 §5(a) change notices. |
| `app/test/translation_keys_test.dart`, `app/test/translation_override_loader_test.dart` | **New.** |

## 6. A bug found and fixed along the way

`RootBundleAssetLoaderCustomLocaleLoader.getLocalePath` special-cased `zh_Hant`/`pt_PT` by reading
`appStateSettings["locale"]` — **including on the fallback (`en`) load**, since
`useFallbackTranslations: true` runs the fallback through the same loader. So a `zh_Hant` or `pt_PT`
user's "English fallback" was actually their own language again, and any of the fork's 109 keys
missing from that file rendered as a raw key string instead of English. Dropping both variants (they
are not in the trimmed 8) removed the branch and the bug with it.

## 7. Non-goals

- No machine translation, no external translation API.
- No server-side sync of overrides (§3).
- No Weblate/Crowdin integration, no `CONTRIBUTING-TRANSLATIONS.md` (§3) — the format keeps that door
  open without opening it.
- No changes to the 6 non-Russian, non-English locales beyond the 12 stale-string fixes and the 5 new
  keys; they remain upstream community translators' work, credited in
  `app/assets/translations/README.md`.

## 8. Acceptance criteria

- [ ] Switching to Russian reads naturally throughout the app, including on the account/login screens.
- [ ] Settings → Language → Edit translations: search, edit, save — the UI updates immediately, no
      restart.
- [ ] The edit survives an app restart.
- [ ] Filtering by "Missing here" on German lists the fork's onboarding/account strings, not the whole
      app.
- [ ] Export, revert everything, re-import: the edits come back.
- [ ] The language picker no longer shows a card linking to `dapperappdeveloper@gmail.com`.
- [ ] An install previously set to a now-dropped language (e.g. Japanese) comes up in English after
      updating, with the picker showing "System" rather than the stale language.
- [ ] `dart run tool/merge_translation_overrides.dart --self-test` passes from a clean checkout.
