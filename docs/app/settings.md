# Settings, and what follows a person between devices

File: `app/lib/struct/perUserViewSettings.dart`.

## The `AppSettings` table has two kinds of row

| Row | Contents | Synced |
|---|---|---|
| `0` | the whole shared-preferences blob written by `backupSettings()` — server URL, signed-in email, cached exchange rates | **never** |
| `<userId>` | that member's view preferences, allow-listed keys only | yes |

**Row 0's exclusion from the change feed (`getAllNewAppSettings`) is the safety property that makes
syncing this table acceptable at all.** It carries the server URL, the signed-in email and cached
rates — none of which should travel to another person's device. A change here that syncs the table
"consistently, all rows" is a data leak, not a cleanup.

## What is allowed to travel

A short allow-list (`syncedViewSettingKeys`), not the whole settings map: hidden wallets, home-page
section order and visibility, the wallet switcher, and the selected account. Most of
`appStateSettings` is device-local (server URL, cached rates, which platform's icons to draw) or
account-wide, and syncing it wholesale would move all of that too. **Add keys one at a time** — each
addition is a decision that the setting follows the person rather than the device.

**Note what this mechanism cannot do**, because it has been reached for and turned down once: it has
no *household-wide* setting. Rows are keyed by user id, so a preference everyone sharing the data
should agree on has nowhere to live here. The envelope order is the worked example — it wanted to be
one order for the whole household, so it is `Categories.order`, an ordinary synced column, and not a
setting at all. See [envelopes.md](envelopes.md).

The same shape rules out per-account order today for a different reason: a row only exists when the
signed-in profile shares a household (see below), so on a solo account these keys never leave the
device. Anything that must follow one person between their own phone and laptop, household or not,
needs that rule revisited first.

Shared preferences was not an option: it is per device, so a member's phone and laptop would never
agree. A column on `Wallets` was not either — unlike `Budgets`, `Wallets` has no dead column to
borrow, so it would have been the first deliberate break of the schema-identical invariant. A row in
a table that already exists costs neither.

## Only on shared accounts

A row exists only when the signed-in profile actually shares a household. On a solo account there is
nobody to differ from, so a synced row would be pure overhead — and it would start being pushed the
moment a second member joined, without anyone asking for it.

## Two details that look like noise and are not

- **`_applyingStoredViewSettings`.** `updateSettings` mirrors every allow-listed key into the
  member's row, which is right when a person changes something and wrong when the change arrived from
  their other device: keys apply one at a time, so each write would store a half-applied mixture
  under a fresh timestamp and push it back. It settles on its own, but the round trip is pointless,
  so it is suppressed.
- **Comparing values as encoded JSON.** These values include lists, and two equal lists are not `==`
  in Dart — a plain comparison reports every list-valued preference as changed on every sync.

A malformed row is logged and ignored rather than thrown: these are screen preferences, and they must
not stop the app starting or a sync completing.

`applyStoredViewSettings()` runs after a sync cycle applies an `AppSetting` change, so a preference
changed on this member's other device shows up without a restart.

## Translations

Not here — the fork's own 8 locales, the in-app editor and the merge tool are described in
`app/assets/translations/README.md`.

---

Why: `specs/06-shared-household-data.md` (per-user views),
`specs/backlog/BL-007-fork-owned-translations.md` (locales).
