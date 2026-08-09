# BL-004 — Public README.md for the GitHub Repo, Describing Self-Hosted Deployment

**Status:** Reviewed. **Not approved for implementation.** Two framing decisions in §5 affect what
"pretty" should mean here; content sourcing otherwise is straightforward.

**Origin:** owner-submitted, 2026-08-09.

**Local-first / sync check:** ✅ N/A. Documentation only — no app/server code.

---

## 1. What's being asked

A root `README.md` for `github.com/vfyuj/cashew-selfhosted`, written for someone landing on the repo
page, that explains what the project is and how to deploy it on a self-hosted server.

---

## 2. Verified current state

No root README exists — `find . -maxdepth 1 -iname "README*"` returns nothing. GitHub's own repo
front page currently renders blank. What exists instead:

- **`DEPLOYMENT.md`** — a detailed, accurate runbook, but written *to the owner specifically*: "your
  home server", "wherever Nextcloud/Immich already run", NPM click-paths. Good content, wrong voice
  for a landing page — it assumes the reader already knows what this project is and skips straight to
  step 5 of "how do I deploy this." No screenshots, no license/attribution section, no "what is this"
  paragraph.
- **`CLAUDE.md`** — agent-facing instructions (repo layout, testing workflow), not written for a
  human visitor.
- **`specs/00-overview.md`** — the actual source of what/why (rationale, principles, tech stack),
  written tersely for AI agents. Good raw material to condense from, not itself pretty or
  public-voiced.
- **`LICENSE`** — present (GPL-3.0 full text, 35KB) but not summarized or linked from anywhere a
  casual visitor would see first, since there's no README pointing at it.

---

## 3. Not just a nicety — GPL-3.0 attribution

`specs/00-overview.md` principle 5 already commits to: *"GPL-3.0 compliance. Keep LICENSE and
copyright notices. Source stays available (public repo). Fork identity... must be distinct from
upstream before any distribution beyond the owner's own devices."* A README is the natural place to
do the part of that which isn't yet done anywhere visible: explicitly crediting
[jameskokoska/Cashew](https://github.com/jameskokoska/Cashew) as the project this was forked from,
alongside a license section — both the honest thing to do and the customary norm for GPL forks,
independent of exact legal necessity.

This also connects to [BL-003](BL-003-upstream-legacy-translations-and-docs.md) §4: once this README
exists, it's a real fork-owned page the in-app "app-is-open-source" link (`aboutPage.dart:858`) can
point at instead of upstream's repo.

---

## 4. Suggested contents (shape, not a template to fill in blindly)

- Project name/tagline, 1-2 sentence description — self-hosted budgeting app, fork of Cashew.
- **Why this fork exists** — condensed from `specs/00-overview.md`'s "Why" section (Google auth/sync
  pain points; upstream's reasonable, stated decision not to host multi-user sync themselves).
- **Screenshot(s)** — none exist anywhere in the repo today; would need to be captured from a running
  instance, not fabricated.
- **Feature/status summary** — human-readable version of `CLAUDE.md`'s Status section (what's
  implemented, what isn't yet), not a copy-paste of the agent-facing checkboxes.
- **Quickstart** — `git clone` + `docker compose up --build`, matching `DEPLOYMENT.md` §1 exactly
  rather than inventing a second, possibly-drifting version of the same steps — then link out to
  `DEPLOYMENT.md` for the full DNS/NPM runbook instead of duplicating it.
- **License & attribution** — GPL-3.0, link to `LICENSE`, explicit "fork of jameskokoska/Cashew"
  credit and link (§3).
- Link to `specs/` for anyone (owner, future collaborator, or future agent) wanting the full design
  rationale.

---

## 5. Open decisions needed from owner

1. **Audience.** Is this repo meant to stay "public but effectively personal" (the owner's own
   project, happens to be on GitHub) rather than something actively seeking outside users or
   contributors? If so, "pretty" likely means *clear and complete for future-owner-self*, not
   *optimized to attract contributors* — e.g. skip contribution guidelines, issue templates, or
   maintenance-implying badges. Affects tone throughout §4, not just one section.
2. **Screenshots: yes/no, and from where?** If yes, they need to come from an actual running
   instance — not something to generate or fake.

These two are worth deciding together with the link-audience question already raised in
[BL-003](BL-003-upstream-legacy-translations-and-docs.md) §3, since the same "who is this repo really
for" answer shapes both.

---

## 6. Files touched

| File | Role |
|---|---|
| `README.md` (new, repo root) | The public-facing landing page described above |
