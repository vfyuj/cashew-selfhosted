# Release Notes Style Guide

**Status:** guideline adopted 2026-08-10, ahead of the first real release. Not yet applied to a shipped changelog entry — the checklist at the bottom is what "applied" will look like.

## Why this exists

`07-versioning.md` already specifies the *mechanics* of this fork's changelog: the file it lives in, the parser format (`    < 1.0.0-beta.14` headings, four-space indent, bullets), and the rule that a version with no section shows no popup. What it doesn't specify is *what to write* — how to decide whether a change earns a line, how to phrase one, how much is too much. Before the first release ships, it's worth having that settled rather than improvised per-entry.

This fork's changelog culture already leans the same direction on its own — "add a section only when a change is worth interrupting someone for" is already the rule in `07-versioning.md` and in `CLAUDE.md`. Immich's approach (below) is the same instinct carried all the way through, with enough structure to reuse deliberately instead of by feel.

## The source

Immich doesn't publish this as policy — nothing about it is in their `CONTRIBUTING.md` or docs. What follows is an analysis pulled from reading many of Immich's actual releases (GitHub Releases, the mirrored posts on the immich.app blog, the in-app "what's new" behavior), adopted here because it matches this project's own instincts about not interrupting people for nothing.

### The one idea everything else follows from

Every Immich release is really two separate documents, for two different readers:

1. **The story** — a short, hand-written, illustrated "Highlights" section for everyday users. Selective. Warm. Skippable.
2. **The ledger** — an exhaustive, automatically generated list of every merged pull request, grouped under plain category headers (Breaking Changes, Security, Features, Enhancements, Bug Fixes, Documentation, Translations). For developers, packagers, and anyone auditing exactly what changed.

The ledger is complete on purpose — nothing gets filtered out, because its job is trust and traceability. The story is selective on purpose — because its job is comprehension, not completeness. Almost every rule below is really about writing the story well, and keeping it visually and editorially separate from the ledger.

### Rule 1 — Make the interruption tiny; make the reading optional

Nothing about updating Immich forces anyone to read anything. The signal that a new version exists is small and low-key — a quiet notice with a link, never a blocking dialog, never the changelog text itself. The "what's new" screen is a lightweight, dismissible sheet, not a full-screen takeover, and it's deliberately *not* shown to someone logging in for the first time, since a highlights reel means nothing to someone with no "before" to compare it to.

The pattern everywhere is: notice → link → (only if you choose) the full story. Never: notice → forced full story.

**Reusable version:** treat "something changed" and "here's what changed" as two different surfaces. The first should be almost invisible. The second should be one click away and never forced on anyone — including never forced on brand-new users who have nothing to compare it to.

### Rule 2 — Curate. Most changes don't earn a sentence

A real release might contain dozens of merged changes. The hand-written "story" only ever mentions a handful.

**Earns a highlight** (a heading, a short paragraph, a picture):
- A new page, panel, or capability a regular user would notice unprompted
- A workflow change people will feel (something got meaningfully faster, something moved)
- Anything being removed or restricted that people relied on — always disclosed, never buried
- Breaking changes — always mentioned, but as a short pointer to a dedicated migration guide, never as inline technical detail

**Stays in the ledger only:** routine bug fixes, refactors, dependency bumps, internal API cleanup, most translation updates, anything a user has no practical way of noticing.

**Effort scales with the release.** A patch or hotfix gets one plain sentence at the top — something like *"Fixes a crash when opening shared albums on iOS"* — and nothing else; no highlights section gets manufactured just to have one. A minor or major release, where there's an actual story, gets the full treatment. Padding a quiet release to look bigger than it is would break the whole pattern.

### Rule 3 — One feature, one small, repeatable block

Each highlighted feature follows roughly the same shape:

1. **Heading** — the feature's name in plain words, not its internal/technical name
2. **One context sentence** — why now: a follow-up to something earlier, a long-requested item, or an explicit "preview" that isn't finished
3. **One or two benefit sentences** — what the user can now *do*, described as an action and an outcome, rather than as an implementation detail
4. **Where to find it** — the literal menu path, so the description doubles as instructions
5. **One picture** — a screenshot or short recording placed right after the text; not a gallery
6. **An optional, honest caveat** — for anything still in preview: what isn't there yet, and where to send feedback

If a feature needs more than a few sentences to explain, that's a sign it belongs in documentation, not in a highlight.

### Rule 4 — The in-app copy is a second, shorter rewrite, not a copy-paste

On mobile, each highlight that makes it into the app itself is stored as plain data, not prose: a short title, one line of body text, and — only when it's genuinely useful — a small hint about where to find the feature. There's no field for the context sentence or the caveat, and no picture. If a highlight needs more than a title and a single sentence, it doesn't fit the in-app format at all, and it simply stays a GitHub/blog-only highlight.

A few structural choices worth copying:
- **Title and body are separate fields, and the body is capped at essentially one sentence.** A distillation of the fuller paragraph, not the same text reused in a smaller box.
- **There's no picture — just an optional pointer to where the feature lives.**
- **Entries can be scoped to a single platform.** Nobody sees a highlight for something their device doesn't have.
- **Not every release gets a batch.** The set of in-app highlights is tied to its own hand-set "content version," kept deliberately separate from the app's real build number — bumped only when maintainers decide a new batch is ready, never automatically on every release.
- **It isn't only a one-time popup.** The same batch stays reachable afterward from a permanent "What's new" entry in settings, labeled with the version it was written for.

**Reusable version:** write the fuller version for the changelog first. Then, separately, compress each highlight you also want to surface in-app down to a title and one sentence — don't just reuse the paragraph, and don't reach for a screenshot. Store it as data (title, one line, optional location hint, optional platform tag) rather than as formatted text, and give that batch its own version marker so publishing it in-app is a deliberate decision, not something that fires automatically on every build.

### Rule 5 — Voice: sound like the people who built it

First person plural — "we," never a third-person announcement voice. Outcomes before mechanisms; plain words over feature-speak. Willing to name what got worse or disappeared, in the same breath as what got better, instead of only celebrating. A little personality is fine as long as it seasons the information instead of replacing it. A quiet release is allowed to say, in one line, that it was quiet — nobody manufactures excitement for its own sake.

### Rule 6 — Design for skimming, and give it a clean place to be read

A plain bulleted list of every highlighted feature's *name* sits right under "Highlights," before any prose — a table of contents so someone can jump straight to the one thing they care about. Every feature gets its own heading, so scanning headings alone still gives a real, if shallow, summary. Long release notes get truncated with a "read more," never dumped in full at first contact.

### Rule 7 — Say what will break, once, clearly, then point away from the noise

Breaking changes get a short, clearly labeled section near the top: a visible warning, one plain-language line about who's actually affected (often: mostly integrations and power users, not everyday people), the exact steps needed to update, and a link to a separate, dedicated migration guide for anyone who needs the full detail. The inline note stays deliberately short — depth lives one click away, not inside the highlight itself.

### The checklist

- [ ] Does this release have an actual story, or is it mostly routine? If routine: one or two plain sentences, done.
- [ ] For each candidate feature — would a regular user notice this on their own? If not, ledger only.
- [ ] Does anything get removed, restricted, or start behaving differently? Say so plainly, next to what's new, not in a separate buried list.
- [ ] Are there breaking changes? Give them a short, separate, clearly labeled section — link out for detail, don't inline it.
- [ ] Is the "something changed" notice separate from the "here's what changed" explanation? The first should be near-invisible; the second should be optional.
- [ ] Would a brand-new user see this "what's new" content with nothing to compare it to? If so, suppress it for them specifically.
- [ ] For anything also going in-app: have I compressed it a second time — title, one sentence, and at most a short location hint, no picture — instead of reusing the fuller paragraph?

### Fill-in template for one feature entry (the fuller, GitHub/write-up version)

```
### [Feature name, in plain words]

[One sentence: why this exists, what it follows up on, or whether it's a preview.]

[One or two sentences: what the user can now do — action and outcome, not
implementation.]

You'll find it in [exact menu path].

[Optional: what's not here yet, and where to leave feedback.]
```

### Fill-in template for one in-app highlight (tighter — bottom-sheet format)

```
Title: [2-6 words, plain; often phrased as the action or the benefit]
Body: [exactly one sentence, second person, the outcome only — no context, no caveat]
Where to find it: [optional — a menu path or setting name, only if not obvious.]
Platforms: [all, or only the ones where this is actually true]
```

## How this maps onto this fork today

The abstract rules above assume infrastructure Immich has and this fork doesn't (yet). Concretely, right now:

| Immich concept | This fork's equivalent |
|---|---|
| The story (hand-written highlights) | The bullets under a `< 1.0.0-beta.N` heading in `getChangelogString()` (`app/lib/widgets/showChangelog.dart`) — see `07-versioning.md` § "The changelog" for the exact parser format |
| The ledger (auto-generated, categorized, every PR) | `git log`/the GitHub compare view between tags. There's no automated generator wired up — this is a single-owner fork without a PR queue to summarize, so the ledger is just the commit history, not a published document |
| In-app highlight cards with a title + icon, tappable | `getMajorChanges()`, today an empty extension point (see comment in `showChangelog.dart`) |
| Platform-scoped entries | Already supported: a line containing `(A)` shows only on Android, `(i)` only on iOS, per the existing parser in `getChangelogPointsWidgets` |
| A separate "content version" for in-app highlight batches, distinct from the build number | Doesn't exist. `getMajorChanges()` is keyed by the same version string as the plain changelog, so a highlight batch and a changelog section always ship together, not on independent schedules |
| Blog mirror of release notes | Doesn't exist — no public blog for this fork |
| Dedicated migration guide page for breaking changes | Doesn't exist yet. Until Stage 4 or a similarly disruptive change actually ships a breaking change, "link to a migration guide" means: write the detail in the relevant `specs/*.md` file and link that section from the changelog line, rather than inlining it |

**What to actually do, in order, for each release:**

1. Look at what shipped since the last version with a changelog section (Rule 2). If it's routine — bug fixes, refactors, dependency bumps — write one plain sentence, or add no section at all.
2. If there's a real story, draft each highlight using the feature-entry template above. Keep it to what a user would notice unprompted.
3. Compress anything worth surfacing as a `getMajorChanges()` card down to title + one sentence + optional location hint, per Rule 4 — only once `getMajorChanges()` actually gets populated for a release; it's fine to ship changelog-only entries indefinitely if nothing merits a card.
4. If anything breaks or is removed, say so in the same section as what's new (Rule 7), not buried — this fork doesn't have a separate migration-guide page yet, so link to the relevant spec file instead.
5. Write in first person plural, outcomes over mechanisms (Rule 5). This is already how `07-versioning.md` and existing changelog entries in `showChangelog.dart` read — keep it that way.

## Non-goals (for now)

- **No automated PR-ledger generator.** Reasonable to add later if this fork ever has enough contributors/PRs to make hand-tracking painful; not needed today. If it becomes worth building, it's a backlog candidate, not something to bolt on mid-release.
- **No separate in-app "content version" for highlight batches**, independent of the build number. `getMajorChanges()` stays keyed to the plain version string until there's an actual reason to decouple them.
- **No blog mirror.** This fork has no public blog; the in-app changelog and the repo's release history are the only surfaces.
- **No images/screenshots embedded in changelog entries.** `showChangelog.dart`'s widget is plain text + optional tappable card; adding image rendering there is out of scope unless a future spec asks for it.

## Acceptance criteria

- [ ] The first release that ships a changelog section is written using the curation rule (Rule 2) and the block shape (Rule 3) above, not just narrated as "misc changes."
- [ ] Any breaking change in a release gets Rule 7's short, separate, clearly-labeled treatment rather than being folded into an ordinary bullet.
- [ ] Routine/internal-only changes (refactors, dependency bumps, most translation updates) are left out of `getChangelogString()` entirely rather than padding a quiet release.
