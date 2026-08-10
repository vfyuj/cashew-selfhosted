# BL-005 — Receipt scanning over IMAP (replacement for Gmail scanning)

**Status:** Not started. Written 2026-08-10, when the Gmail-backed version was deleted as part of the
full Google removal (`specs/03-stage-1-kill-google.md`).

**Origin:** owner asked for the fork to be de-Googled completely. Gmail receipt scanning was the one
removed feature with no equivalent left in the app, so this records what it did and what a
provider-neutral replacement would need.

---

## 1. What was removed

Upstream Cashew could read the user's Gmail and turn matching messages into transactions:

- OAuth to Google with `gmailReadonlyScope` + `gmailModifyScope` (the latter only to mark messages read).
- `GmailApiScreen` listed recent messages; the user picked one and built a **scanner template** from it
  by marking the text immediately before and after the title and the amount.
- Templates were stored in the `scannerTemplates` Drift table (still present — the schema is unchanged).
- `parseEmailsInBackground` re-ran on pull-to-refresh and at launch, matching new mail against templates
  and queueing transactions.

## 2. What survived

Everything that isn't Google-specific, because the same template mechanism also drives Android
notification scanning:

- `scannerTemplates` table and all its columns.
- `lib/pages/autoTransactionsPageNotifications.dart` — the notification listener, the template editor
  entry points, `ScannerTemplateEntry`, `EmailsList` (despite the name it renders captured message
  bodies, not mail), and the two parsers `getTransactionTitleFromEmail` /
  `getTransactionAmountFromEmail`.
- `lib/pages/addEmailTemplate.dart` — the template editor itself.

So a replacement only needs a **message source**. The parsing, storage, editing and
transaction-queueing halves already exist and are provider-neutral.

## 3. What a replacement needs

Speak IMAP directly to whatever mail server the user already has, with no third party in the middle.

- Settings: host, port, TLS on/off, username, password, folder (default `INBOX`), and a sender/subject
  filter so the app fetches a narrow slice rather than all mail.
- Fetch: `SEARCH` for unseen messages matching the filter, `FETCH` body text, hand each to the existing
  template matcher. Never delete; marking read should be opt-in, as it was with Gmail.
- Credentials go in app settings like the WebDAV backup target's do (`lib/struct/webdavClient.dart` is
  the closest existing precedent — hand-rolled protocol client, no new dependency, configured entirely
  client-side).

## 4. Constraints and open questions

- **Local-first (`01-local-first-invariant.md`)**: scanning must stay a background, best-effort action.
  An unreachable mail server pauses scanning; it never blocks launch or any user flow.
- **The server stays out of it.** Same rule as WebDAV backup: the app talks to the mail host directly.
  Do not add a mail client to `/server`.
- **Web builds cannot do this.** IMAP is a raw TCP protocol and a browser cannot open one. Either the
  feature is Android-only (the same platform restriction notification scanning already has), or it
  needs a server-side fetcher — which contradicts the point above. Decide before building.
  This is the main reason the work wasn't attempted inline with the Google removal.
- **Dependency question.** A hand-rolled IMAP client is considerably more protocol than the WebDAV one
  (IMAP is stateful and its grammar is awkward). Using `enough_mail` is the realistic alternative and
  would be the first non-trivial new dependency in a while — worth an explicit decision rather than a
  drive-by `pub add`.
- **Password storage.** Mail passwords are higher-value than the WebDAV ones already stored in app
  settings. Consider app-specific passwords / OAuth-less providers only, and say so in the UI.

## 5. Acceptance criteria

- A template built from a real receipt email creates the right transaction, with the same editor flow
  the notification path uses today.
- No mail credentials leave the device, and nothing about this reaches `/server`.
- Airplane-mode test still passes with scanning configured (`01-local-first-invariant.md`).
- Turning the feature off leaves the `scannerTemplates` rows intact, so notification scanning is
  unaffected.
