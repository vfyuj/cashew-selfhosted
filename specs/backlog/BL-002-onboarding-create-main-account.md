# BL-002 — Onboarding: accounts, categories, and setting the envelope plan

**Status:** **Implemented 2026-08-10.** Superseded the original single-screen copy change — the owner
approved a wider rework at the same time (see §1). The original review of the narrow version is kept
in §7 for its still-valid constraints (translations pipeline, key placement).

**Origin:** owner-submitted, 2026-08-09. Scope widened by the owner, 2026-08-10.

**Depends on [BL-001](BL-001-category-locked-budgets.md).** The planning steps set amounts on the
envelope budgets BL-001 auto-creates, one per main category. A first cut of this work was written
against a checkout that predated BL-001 landing and created a standalone catch-all budget instead;
that was wrong once envelopes existed — see §2.

The onboarding steps write to Drift the same way the rest of the app does (wallets, categories,
budgets); no schema change. The one new network call — the "does this account already have data"
probe in §3 — is best-effort, bounded to 8 seconds, and fails towards "just run onboarding," so it
never gates local usage.

---

## 1. What was built

Onboarding went from 3 steps to 5. Nothing in it is mandatory: every step can be skipped, and the
first step can end onboarding outright.

| # | Title key | Content |
|---|---|---|
| 1 | `onboarding-title-1` | Unchanged pitch copy. Now carries **two** floating buttons: the existing Preview Demo, and a new **Skip Setup** under it that ends onboarding immediately (`onboarding-skip-setup`) |
| 2 | `onboarding-title-2` → **"Set up your accounts"** | What-is-an-account explainer (`onboarding-account-explainer`), the live list of accounts with each one's **balance and currency** (tap to rename / set an opening balance / change currency via `AddWalletPage`), and **Add Account** |
| 3 | `onboarding-title-categories` | The categories as tappable icons (tap to rename/recolour/delete via `AddCategoryPage`), plus **Add Category**. Explains that each category carries its own monthly budget, so this list is the shape of the plan |
| 4 | `onboarding-title-income` | One row per **income** main category, each setting that category's envelope amount |
| 5 | `onboarding-title-budget` | Explains what an expense planning budget *is*, then one row per **expense** main category setting its envelope amount, a Planned expenses / Planned income / **Budget plan balance** footer, and **Let's Go!** |

Both planning steps handle "the user deleted every category of this type on step 3" with an explicit
message and an **Add Income/Expense Category** button, rather than rendering an empty gap under a
paragraph telling them to fill something in.

Explanatory copy is capped at 600px wide and puts each sentence on its own line (literal `\n` in the
strings). Unconstrained, a paragraph runs the full width of a desktop browser window, which reads
badly against the narrow controls beneath it.

**Order note:** categories come *before* the two planning steps because [BL-001](BL-001-category-locked-budgets.md)'s
envelopes are derived from the category list — the plan literally has one row per main category, so
reviewing that list first is what makes steps 4 and 5 make sense.

The old step 3 ("Welcome to {app}!" + sign-in status + Let's Go) is **gone**. It existed to confirm
sign-in state, which the first-run server wizard already does before onboarding starts; its only
unique element was the finish button, now on step 5.

Deviations from the original request, both deliberate:

- **Title is "Set up your accounts", not "Create main account".** The screen now manages *any* number
  of accounts, so the singular framing would have been wrong. This also settles §4's open decision
  below in favour of a variant of option (b): the account can be renamed here, but through the
  existing `AddWalletPage` rather than a bespoke inline text field, so there is no second code path
  to keep in step with account editing elsewhere.
- **The "change currency" shortcut button was removed** from step 2. Currency is now reached by
  tapping the account itself, alongside its name, colour and icon — one affordance instead of two,
  and it no longer implies currency is the only thing you can change here.

### Skipping

- Step 1: **Skip Setup** → `nextNavigation()`, i.e. finish onboarding now.
- Steps 2–4: **Skip This Step** (`onboarding-skip-step`) → advance one page. Same thing the forward
  arrow does; stated in words so skipping doesn't depend on noticing an icon. Rendered inline at the
  end of the step, not floated like step 1's buttons — these steps grow with the number of accounts
  or categories on screen, and a floating button would sit on top of them.
- Step 5: any category left at 0 is simply an unplanned category, which is the envelope system's own
  resting state.

Skipping writes nothing at all. `nextNavigation()` no longer creates any budget — it only flips
`hasOnboarded` — so someone who taps straight through ends up in exactly the state
`initializeDefaultDatabase()` would have left them in anyway: one account, the default categories,
and a zero-target envelope for each.

---

## 2. The planning steps edit envelopes; they create nothing

Steps 4 and 5 are the same widget (`envelopeList`) filtered by `TransactionCategory.income`. Each row
is one main category; tapping it opens `SelectAmount` and writes the result to that category's
envelope budget with `createOrUpdateBudget(..., updateSharedEntry: false)` — the same guard against
the dead Firestore branch that `ensureMainCategoryBudgetsExist()` uses.

Three details worth keeping:

- **The envelope is found by `categoryFks`, not by `budgetPk == categoryPk`** (`_envelopeFor` in
  `onBoardingPage.dart`), mirroring `PlannedBudgetTotals.isMainCategoryBudget`. Auto-created
  envelopes are keyed by the category pk, but one adopted from a pre-existing hand-made budget keeps
  the pk it already had, and onboarding must edit that one rather than miss it.
- **The write happens once, after the sheet closes** — not in `setSelectedAmount`, which
  `SelectAmount` fires on every keystroke. Each write is a row the live sync feed has to carry.
- **Balance Correction (pk `"0"`) is filtered out** of every list here, matching
  `_isEnvelopeEligible`. On a fresh install it does not exist yet anyway — it is created lazily by
  the first account correction or transfer.

### What this replaced, and why it was wrong

The first cut of this work was written against a checkout that predated BL-001. Its income step
created a standalone `Budget` (no `categoryFks`, `income: true`, named "Income") and its final step
kept the old `BudgetDetails` amount/period/date controls to create a catch-all expense budget. Both
were correct against the old model and wrong against the envelope one:

- The income category already has an envelope, so a second income budget **double-counted planned
  income** — `PlannedBudgetTotals.totalPlannedIncome` sums *every* budget with `income == true`,
  which is exactly the denominator the "% of planned income" entry divides by.
- The catch-all expense budget is not a main-category budget, so it landed in the budgets list's
  **Custom** tab as a stray row next to the twelve envelopes that are the real plan, and contributed
  nothing to planned expenses or to the Planned vs. Actual card.

The `default-income-budget-name` key added for that version was removed again with it.

---

## 2b. Opening balance on an unused account

Reported from the first fresh-start test: opening the auto-created "Bank" account offered **Correct
Total Balance** but no "Starting at…" field, so there was no obvious way to say what is actually in
the account — the first thing anyone wants to enter.

`AddWalletPage` showed "Starting at…" only when `widget.wallet == null` (creating). It now shows it
whenever the account is **unused** — being created, *or* being edited with zero transactions
(`isUnusedAccount`, backed by the new
`FinanceDatabase.getTotalCountOfTransactionsInWallet`). "Correct Total Balance" is hidden in that
same case, so exactly one of the two is ever on screen: an account with nothing in it has an opening
balance to set, not a total to be out of step with.

Both paths post the same balance-correction transaction through `correctWalletBalance` — for an
unused account the current total is 0, so the difference and the new total are the entered amount
either way. `initialBalance` is zeroed after posting, because `addWallet(popContext: false)` runs a
second time on the Correct Total Balance and Transfer Balance paths and would otherwise post the
opening balance twice.

This is a change to a page used throughout the app, not just onboarding. It is deliberate: the same
confusion applies to any account created for you or added and left empty.

---

## 3. The new-device bug this also fixed

**Symptom:** signing in to an existing account on a second device ran the whole onboarding flow
again, asking for accounts, categories and a budget that already existed on the server and were about
to sync down.

**Cause:** `hasOnboarded` is a device-local setting (`app/lib/struct/defaultPreferences.dart:127`).
Sync moves Drift rows, not settings, so a fresh install of the app starts at `hasOnboarded == false`
regardless of how much data the account it just signed into already holds.

**Fix:** `selfHostedAccountHasExistingData()` in `app/lib/struct/selfHostedClient.dart` asks the
server whether this account has anything yet — `GET /sync/pull?since=0&limit=1` for the Stage 2
row-level feed, falling back to `GET /sync/files` for accounts last used by a build that predates it.
A `409 rebootstrap` counts as "yes": only an account already in use can have had its feed reset.
`_finishAfterAuth()` in `serverSetupWizardPage.dart` calls it after a successful sign-in or setup and
sets `hasOnboarded` when the answer is yes.

Deliberate properties:

- **Fails towards showing onboarding.** Unreachable, timed out, signed out, malformed response — all
  return false. Getting it wrong that way costs one skippable screen; getting it wrong the other way
  would drop someone into an app whose data hasn't arrived yet with no explanation.
- **Bounded to 8 seconds**, shorter than the client's own per-request timeouts, because someone is
  watching a sign-in complete. The wizard shows its existing "checking server" step while it runs.
- **Setup vs. sign-in is not the discriminator.** An administrator provisioning a second household
  member creates an account that is new *and* reached through the sign-in path, so the question has
  to be about the account's data, not about which form was used.

---

## 4. Original open decision — now closed

1. ~~**Scope: (a) label-only swap, or (b) also add an account-name field?**~~ Resolved as a variant of
   (b): renaming happens on this screen, via the existing `AddWalletPage`, reached by tapping the
   account. See §1.

---

## 5. Files touched

| File | Role |
|---|---|
| `app/lib/pages/onBoardingPage.dart` | The five steps, skip buttons, account list, category grid, envelope amount rows, empty states and the plan totals |
| `app/assets/translations/generated/en.json` | `onboarding-title-2` value change; 14 new keys; removed the two now-dead `onboarding-info-3-*` keys |
| `app/lib/struct/selfHostedClient.dart` | `selfHostedAccountHasExistingData()` |
| `app/lib/pages/serverSetupWizardPage.dart` | `_finishAfterAuth()` on the credentials form's success path |
| `app/lib/pages/addWalletPage.dart` | `isUnusedAccount` — "Starting at…" vs "Correct Total Balance" (§2b) |
| `app/lib/database/tables.dart` | `getTotalCountOfTransactionsInWallet` — query only, **no schema change** |

Not touched, on purpose: `app/lib/database/tables.dart` (no schema change), `translations.csv` and
the 48 non-English locale files (see §7 C1).

---

## 6. What to check when testing

1. **Fresh install** — all five steps appear; each of steps 2–4 can be skipped; Skip Setup on step 1
   lands straight in the app with a working default account, the default categories and a
   zero-target envelope for each.
2. **Step 2** — the default "Bank" account is listed with its balance and currency; tapping it opens
   the account editor showing **"Starting at…"** and *no* "Correct Total Balance"; entering an
   opening balance and saving updates the balance shown on the step. Reopening the same account
   afterwards now shows "Correct Total Balance" instead, and the opening balance is **not** posted
   a second time. Add Account adds a second row.
3. **Step 3** — Balance Correction is **not** listed (it is bookkeeping, and on a fresh install it
   does not exist yet at all). Deleting a default category works and it disappears from the grid;
   adding one makes it appear on steps 4 or 5 according to its income/expense type.
4. **Step 4** — the default "Income" category is listed; setting an amount there and then opening
   the Budgets page shows that amount on the Income envelope under **Main Categories**, and **not**
   an extra budget under **Custom**. Deleting *every* income category on step 3 leaves this step
   showing the empty-state message and an **Add Income Category** button, not a blank gap.
5. **Step 5** — setting amounts updates the expense envelopes in place; the footer shows Planned
   expenses, Planned income, and **Budget plan balance** (income − expenses) in green when positive
   and red when negative; the Planned vs. Actual card on the home page agrees with these totals.
6. **The bug** — sign in to an account that already has data from a second browser profile or device.
   Onboarding must not appear. Signing in as a brand-new user provisioned by an administrator *should*
   still show it.

---

## 7. Original review notes, still binding

### C1 — Do not edit `translations.csv` or run `generate-translations.py`

`app/assets/translations/generate-translations.py` downloads a CSV from **upstream's own Google
Sheet** (`generate-translations.py:10`) and overwrites both `translations.csv` and every file in
`generated/` from it. Hand edits to `translations.csv` are silently wiped on the next run.

Precedent followed here, from commit `31baf88`: add fork-specific keys by hand to **`generated/en.json`
only**. `useFallbackTranslations: true` with `fallbackLocale: en`
(`app/lib/struct/languageMap.dart:111-118`) means the other 48 locales render the English string
rather than the key, so this degrades to "untranslated", not "broken".

Consequence worth naming, not fixing: `onboarding-title-2` reuses an upstream key whose 48 other
translations still say "Create a budget". Those stay wrong until upstream's sheet changes or this
fork starts maintaining its own translations — the open question in
[BL-003](BL-003-upstream-legacy-translations-and-docs.md) §2A.

### C2 — Where the source of truth for "main account" is

`initializeDefaultDatabase()` (`app/lib/database/initializeDefaultDatabase.dart`) creates the default
wallet and categories before step 2 ever renders, and `PageNavigationFrameworkState.initState` calls
it again on the main app's first mount. That second call is what makes Skip Setup safe: someone who
never sees a single onboarding step still gets a default account and the default categories.
