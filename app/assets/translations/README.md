# Translations

These files are **maintained here**. They are not generated, and there is no
pipeline to re-run.

## Origin and licence

The files in `generated/` originate from
[jameskokoska/Cashew](https://github.com/jameskokoska/Cashew), `assets/translations/generated/`,
licensed **GPL-3.0**. They were vendored into this fork at its initial commit
(`9fd1ba3`, 2026-08-07), from upstream commit `9cfbe50c16d95429891d44faf5f2c77a3abdb93b`.

Upstream generates those files from a community translation spreadsheet **it
owns**. That spreadsheet is not part of this fork and this fork cannot write to
it. The translations are the work of upstream's community translators; this fork
claims no authorship over them and asks no CLA of its own.

## Changes this fork has made (GPLv3 §5(a))

- **2026-08-12** — Removed the regeneration pipeline (`generate-translations.py`
  and the 2.2 MB `translations.csv` it downloaded). Running it would have
  overwritten this fork's own strings, so it could never actually be run; keeping
  it around only implied otherwise.
- **2026-08-12** — Reduced the shipped languages from 46 to 8 (`en`, `ru`, `de`,
  `es`, `fr`, `pt`, `uk`, `zh`). The other 38 were frozen upstream snapshots that
  nobody here could correct. They remain in git history — restore one with
  `git show 19108a8:app/assets/translations/generated/<lang>.json` and add a row
  to `supportedLocales` in `app/lib/struct/languageMap.dart`.
- **2026-08-12** — Rewrote `ru.json` from scratch against this fork's UI. It is
  fork-authored and no longer derived from upstream's Russian.
- **2026-08-12** — Corrected `onboarding-title-2` and `onboarding-info-3` in
  `de`, `es`, `fr`, `pt`, `uk` and `zh`. Both still translated upstream's English:
  one described creating a budget on a screen that now sets up accounts, the other
  promised that data would be synced with Google Drive.
- **Ongoing** — `en.json` carries ~109 keys that upstream has no equivalent for,
  covering self-hosted accounts, server setup and onboarding.

## How strings are changed now

**In the app.** Settings → Language → *Edit translations* is a searchable list of
every key with its English source and the current translation, editable in place.
Edits apply immediately and are stored on the device — they never touch these
files directly and never sync to the server.

To make an edit permanent for everyone, export it from that screen's overflow
menu and merge it in:

```bash
dart run tool/merge_translation_overrides.dart ~/Downloads/cashew-translation-overrides-2026-08-12.json --dry-run
```

Drop `--dry-run` to write. Then clear the overrides in the app, or they will keep
shadowing the shipped values.

**By hand.** Flat `key: string` JSON, one file per language, two-space indent, no
trailing newline, non-ASCII written literally rather than escaped. Every key must
exist in `en.json` — `app/test/translation_keys_test.dart` fails the build
otherwise. Other languages may omit keys; they fall back to English.

## Why the format is what it is

Flat per-language JSON is what Weblate and Crowdin both consume natively. If this
fork ever wants outside translators, either can be pointed at `generated/`
directly with no migration. That was the real cost of upstream's spreadsheet, and
the reason for not replacing it with another bespoke format.
