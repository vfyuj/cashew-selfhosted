# BL-002 — Onboarding Screen 2: "Create a budget" → "Create main account", with a What-is-an-Account explainer

**Status:** Reviewed. **Not approved for implementation.** One product decision in §4 needs the
owner's answer; the rest is a small, low-risk copy change.

**Origin:** owner-submitted, 2026-08-09.

**Local-first / sync check:** ✅ N/A. This is a static UI string change — no Drift table, no sync
payload, no auth/connectivity involved. Doesn't touch `specs/01-local-first-invariant.md` or the
sync path at all.

---

## 1. What the request asks for

On the onboarding flow's second screen, replace the title **"Create a budget"** with **"Create main
account"**, and add an explanatory blurb — sourced from Cashew's docs — answering "What is an
Account?":

> An account represents a place where money is stored or spent from (e.g., bank account, cash
> wallet, credit card, savings). All transactions are saved against a single account in the account
> currency.

---

## 2. Verified against source

The onboarding flow is `OnBoardingPageBody` in `app/lib/pages/onBoardingPage.dart`, `numPages = 3`
(`onBoardingPage.dart:190`). Confirmed exactly 3 active pages (one earlier block, lines ~194–229, is
commented out and doesn't count):

| Page | Title key | Value | Content |
|---|---|---|---|
| 1 | `onboarding-title-1` | "Track your spending habits with {app}!" | Pitch copy only |
| **2** | `onboarding-title-2` | **"Create a budget"** | `BudgetDetails` (amount/period/dates) + a "change currency" button for the primary wallet |
| 3 | `onboarding-title-3` | "Welcome to {app}!" | "Let's go" button, sign-in options |

Page 2 title is rendered at `app/lib/pages/onBoardingPage.dart:283` (`"onboarding-title-2".tr()`),
immediately followed by the `BudgetDetails` widget at line 291. A second, smaller line of text —
`onboarding-info-2-1`, "You can always edit this later." — sits below the currency button, at
`onBoardingPage.dart:406-415`.

Both keys are defined in `app/assets/translations/generated/en.json:71-72`.

**On "account":** the app already uses "Account"/"Accounts" as the user-facing term for what the
code calls `Wallet` (`en.json:12` `"accounts": "Accounts"`, `en.json:487` `"account": "Account"`,
`en.json:830` `"account-label": "Account Label"`), so the new title is consistent with existing
vocabulary, not a new concept. "Main account" itself doesn't appear anywhere in the current strings —
it would be a new but self-explanatory phrase, distinguishing the auto-created default wallet from any
additional accounts the user adds later.

**On timing:** the "main account" isn't actually created *on* this screen. `initializeDefaultDatabase()`
(called from `initState`, `onBoardingPage.dart:158-163`) silently creates it before page 2 ever
renders — `initializeDefaultDatabase.dart:16-21` calls `createOrUpdateWallet(defaultWallet())`, and
`defaultWallet()` (`initializeDefaultDatabase.dart:40-51`) names it via `"default-account-name".tr()`
→ `"Bank"` (`en.json:2`). What page 2 actually lets the user do to that account is change its
**currency** (the "change-currency" button, conditional on the wallet stream having loaded,
`onBoardingPage.dart:346-400`) — there's no field on this screen to rename it away from "Bank". See §3
C2 below — this is the one open question.

---

## 3. Considerations

### C1 — Do not edit `translations.csv` or run `generate-translations.py` for this change

`app/assets/translations/generate-translations.py` downloads a CSV from **upstream's own Google
Sheet** (`generate-translations.py:10`, a `docs.google.com/spreadsheets/...` URL owned by upstream,
not this fork) and overwrites both `translations.csv` and every file in `generated/` from it. Hand
edits to `translations.csv` would be silently wiped the next time anyone runs that script.

This fork already has a working precedent for exactly this situation: commit `31baf88` ("Fix backup
restore not propagating to other synced devices") added three new fork-specific keys
(`safety-backup-created` and friends) by hand-editing **only** `generated/en.json` — not
`translations.csv`, not the other 48 locale files. Verified: none of those keys exist in any locale
file except `en.json`. Follow the same pattern here: edit `generated/en.json` directly, leave
`translations.csv` and the other 48 locale files alone.

Consequence worth naming, not fixing: reusing the existing `onboarding-title-2` key and changing only
its English value means the other 48 languages keep showing their translation of the *old* "Create a
budget" meaning until someone updates upstream's sheet (which this fork doesn't control) or this fork
starts hand-maintaining translations. That's already how the fork's other hand-added strings behave
today — not a regression, just a limitation to accept.

### C2 — Title/content match: does "Create main account" also mean the screen should let you name it?

Right now page 2's only interactive elements are budget fields (amount/period/dates) and a
currency-only button for an account that was already silently created and is still named "Bank"
unless the user later renames it from the Accounts page. Purely swapping the title text leaves a
minor mismatch: the screen *says* "create main account" but the only account-related action on it is
picking a currency.

Three ways to resolve this, cheapest first:
- **(a) Label-only swap.** Change the title and add the explainer text; leave the screen's controls
  untouched. Smallest possible diff, consistent with `CLAUDE.md`'s "prefer small, surgical diffs".
  The title becomes more about *framing* ("this step sets up your main account and its starting
  budget") than a literal description of every control on screen.
- **(b) Add a name field.** Let the user rename the account (pre-filled "Bank") right on this screen,
  so "Create main account" is literally accurate. Bigger diff — needs a text field wired to
  `createOrUpdateWallet`, plus validation.
- **(c) Restructure the screen** to visually separate "your account" (currency + name) from "your
  first budget" (amount/period). Biggest diff, real layout work.

Recommend (a) unless the owner specifically wants the naming affordance — see §4.

### C3 — Where the explainer text goes

Simplest slot: directly under the new title, above `BudgetDetails` (i.e., a new `TextFont` inserted
after `onBoardingPage.dart:289` and before line 291), styled like the existing `onboarding-info-1`
body text on page 1 (`onBoardingPage.dart:254-260`: centered, 16px, not the dimmed 15px/0.35-opacity
style used for the "edit this later" footnote). Keep `onboarding-info-2-1` ("You can always edit this
later.") where it is — it applies to the budget fields, not the account explainer, and the two read
fine stacked (title → account explainer → budget controls → currency button → "edit later" footnote).

---

## 4. Open decision — owner input needed

1. **Scope of the change: (a) label-only swap, or (b) also add an account-name field on this
   screen?** (C2). Recommendation is (a) for a first pass, with (b) left as an optional follow-up
   backlog item if the owner wants the screen to literally match its new title.

Everything else in this document (key reuse, edit location, explainer placement) is an implementation
detail, not a decision that needs to block starting.

---

## 5. Suggested implementation sketch (scope (a))

1. `app/assets/translations/generated/en.json`:
   - Change `onboarding-title-2` value from `"Create a budget"` to `"Create main account"`.
   - Add one new key, e.g. `"onboarding-account-explainer": "An account represents a place where
     money is stored or spent from (e.g., bank account, cash wallet, credit card, savings). All
     transactions are saved against a single account in the account currency."`
2. `app/lib/pages/onBoardingPage.dart`: insert a `TextFont` for `"onboarding-account-explainer".tr()`
   between the title block (ends line 289) and `BudgetDetails` (line 291), matching the page-1 body
   text style (`onBoardingPage.dart:252-260`).

No schema, sync, or non-English-locale changes required. Should be a single small PR.

---

## 6. Files touched

| File | Role |
|---|---|
| `app/assets/translations/generated/en.json` | `onboarding-title-2` value change; new explainer key |
| `app/lib/pages/onBoardingPage.dart` | Insert explainer `TextFont` on page 2 (lines 269-417 block) |
