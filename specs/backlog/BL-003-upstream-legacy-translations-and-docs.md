# BL-003 — Reminder: Decide What To Do With Upstream-Origin Translations and In-App Documentation Links

**Status:** Reminder / inventory only. No fix proposed — this exists so the decision doesn't get
forgotten, per `specs/00-overview.md`'s "this will never be upstreamed, treat it as permanently
diverging." **Not approved for implementation** until the owner picks an option per item in §4.

**Origin:** owner-submitted reminder, 2026-08-09.

**Local-first / sync check:** ✅ N/A. Nothing here is load-bearing for offline app functionality —
it's static translation content and outbound links to upstream's own hosted pages
(FAQ/policy/GitHub/web-app). Safe to change or remove any of it without touching
`specs/01-local-first-invariant.md` or the sync path.

---

## 1. What this is

Fork identity (name/icon/package id) is already finalized per `CLAUDE.md`'s Status section. That
covers branding. It does **not** cover two other categories of upstream leftovers that are still
live in the app today: the translation pipeline, and in-app documentation/links that point at
upstream's own hosted pages instead of anything this fork owns. Both were found while writing BL-002;
this item catalogs them so the "decide what to do about it" step isn't lost.

---

## 2. Known instances (verified against source, 2026-08-09)

### A. Translations pipeline

Full detail already written up in [BL-002](BL-002-onboarding-create-main-account.md) §3 C1:
`app/assets/translations/generate-translations.py` re-downloads `translations.csv` from a Google
Sheet **upstream owns**, then regenerates every file in `app/assets/translations/generated/`. This
fork's own string edits already have to live only in `generated/en.json` by hand (precedent: commit
`31baf88`) because the CSV can't be safely touched — anything written there is wiped on the next
regeneration run.

Open question, no default assumed: keep piggybacking on upstream's sheet forever (free translation
work for 48 languages, at the cost of any fork-specific `en.json` edit slowly drifting out of sync
with what those 48 languages say), fork the sheet into something this project owns and maintains, or
drop non-English locales as out of scope for a single-household self-hosted app and simplify the
pipeline accordingly?

### B. In-app documentation/links pointing at upstream's own hosted assets

| Location | Label key | Target | Why it matters |
|---|---|---|---|
| `app/lib/pages/aboutPage.dart:858` | `app-is-open-source` | `https://github.com/jameskokoska/Cashew` | Points at upstream's repo, not `vfyuj/cashew-selfhosted` |
| `app/lib/pages/aboutPage.dart:866`, `app/lib/pages/settingsPage.dart:110`, `app/lib/widgets/ratingPopup.dart:127`, `app/lib/widgets/importCSV.dart:245`, `app/lib/pages/premiumPage.dart:712` | `guide-and-faq` / inline FAQ links | `https://cashewapp.web.app/faq.html` | Upstream's FAQ describes upstream's Google-based auth/sync/backup flows — inaccurate for this fork's self-hosted flow, not just stale branding |
| `app/lib/pages/aboutPage.dart:907` | `privacy-policy` | `http://cashewapp.web.app/policy.html` | **Highest-priority one.** Almost certainly describes Google/Firebase data handling. This fork's data lives on the owner's own server — presenting upstream's policy as "the privacy policy" here is a real misrepresentation to whoever reads it, not cosmetic staleness |
| `app/lib/pages/aboutPage.dart:996` (`AboutDeepLinking`) | — | `https://github.com/jameskokoska/Cashew?tab=readme-ov-file#app-links` | Upstream's readme section on deep links |
| `app/lib/widgets/accountAndBackup.dart:821` | `web-app` | `https://budget-track.web.app/` | Shown on the **native mobile app's** sync/backup screen as "the web app" — sends a mobile user to upstream's own hosted instance, not this fork's self-hosted web build at the owner's own domain |

### C. Out of scope, listed only to say so

`app/pubspec.yaml:78` — a dependency git URL pointing at `github.com/jameskokoska/reorderable_grid_view`
is a legitimate upstream **package** dependency, not documentation or branding. Not part of this item.

---

## 3. Decision needed from owner

For each row in §2B, pick one:
- **(a) Repoint** at this fork's own equivalent, once one exists (e.g. this fork's own GitHub repo
  for the source-code link; a self-written privacy note for the policy link).
- **(b) Remove** the entry entirely if this fork doesn't want to maintain an equivalent — e.g. drop
  "privacy-policy" rather than keep linking to someone else's policy that no longer describes this
  app's actual data handling.
- **(c) Leave as-is**, explicitly, with a stated reason (e.g. "FAQ content is still mostly accurate
  for shared UI behavior, fine to keep pointing at upstream's for now").

For §2A (translations): keep piggybacking / fork the sheet / English-only — also needs an explicit
answer rather than defaulting by inertia.

---

## 4. Suggested next step (not a full plan)

Once [BL-004](BL-004-public-readme-for-selfhosted-deploy.md)'s README exists, it becomes a real
fork-owned target: repoint `app-is-open-source` (§2B row 1) at it, and if the owner writes even a
short privacy note there, repoint `privacy-policy` (§2B row 3) at that instead of upstream's — that's
the one link in §2B with an actual accuracy problem today, not just staleness. The FAQ and
deep-linking links can reasonably stay pointed at upstream for general Cashew usage help unless this
fork's behavior has diverged enough on those specific topics to need its own version.
