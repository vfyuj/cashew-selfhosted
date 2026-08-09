# Accounts and instance administration

Revises Stage 1's provisioning story. Read `01-local-first-invariant.md` first — the wizard this adds is the *first* thing a new user sees, which makes that invariant easier to break here than anywhere else in the app.

## Status (last updated 2026-08-09)

### Server (`/server`)
- [x] `PRAGMA user_version` migration runner in `lib/src/database.dart`. v1 = the pre-versioning schema (idempotent — deployed instances report version 0 while already having the tables); v2 adds `users.name` and `users.is_admin` and promotes the earliest existing account to administrator.
- [x] `AuthService` extended: profile updates, password change, temp-password generation, user listing, role changes, deletion, with `LastAdminException` guarding against leaving the instance with no administrator.
- [x] `requireAdmin` middleware, composed on top of `requireAuth`. Reads the role from the session per request, so a demotion takes effect immediately.
- [x] `GET /auth/setup-state`, `POST /auth/setup`, `GET|PATCH /auth/me`, `POST /auth/me/password`, and the `/admin/users` family.
- [x] `bin/create_user.dart` is now create-or-reset (it previously promised this in its own output and then threw a raw UNIQUE-constraint error instead).
- [x] Router construction moved to `lib/src/api.dart` so tests exercise the real routing and middleware.
- [x] 34 tests in `server/test/` — the server's first. Plus an end-to-end curl run against a real listening server.

### App (`/app`)
- [x] `lib/pages/serverSetupWizardPage.dart` — the first-run wizard, mounted in `main.dart`'s outer `Stack`.
- [x] `lib/widgets/account/serverCredentialsForm.dart` — shared by the wizard and the account page.
- [x] `lib/widgets/account/` — profile section, edit-profile and change-password sheets, admin user management.
- [x] `autofillHints` threaded through `TextInput`; every credential field wired into an `AutofillGroup`.
- [x] `hasCompletedServerSetup` + `attemptToMigrateServerSetupWizard()`, with 6 tests.
- [x] Onboarding page 3 no longer pushes `AccountsPage`.
- [x] `flutter analyze` reports no errors; `flutter build web --release` succeeds.

### Not done
- [ ] Owner acceptance pass — see "Acceptance criteria" below. Needs a real deployed server.
- [ ] Translations are **English only**. The other 46 languages fall back to English until the maintainer's CSV pipeline is re-run.
- [ ] `flutter build apk` not re-run since these changes (web build is the one verified).

## The bootstrap model

The first person to reach a fresh instance creates the administrator account. Setup then closes permanently. This is what Nextcloud and Immich do, and it replaces "the operator SSHes in and runs a CLI".

- `GET /auth/setup-state` → `{"needsSetup": <the instance has zero users>}`. Unauthenticated, because there is nobody to authenticate as yet.
- `POST /auth/setup` → creates the first user with `is_admin = 1` and returns a session. **409 once any user exists.** The count check and the insert share one transaction, so two simultaneous requests cannot both believe they are first.

### The accepted risk, stated plainly

Between `docker compose up` and the moment the owner registers, anyone who reaches the domain can claim the administrator account. This was an explicit decision, not an oversight: it is the same exposure Immich and Nextcloud accept, and the alternatives (a time-limited setup window, or a setup code printed to the container logs) were weighed and rejected as not worth the friction for a household deployment.

**Operational consequence, which belongs in the deployment docs:** register immediately after the first `docker compose up`, before or right after pointing DNS at it. `GET /auth/setup-state` is the check — if it says `needsSetup: false` and you didn't create that account, someone else did.

## Roles

Two levels, not a permission system: `is_admin` or not. Anything finer waits for `06-shared-household-data.md`, where it would actually have something to protect.

Guards that must not regress:
- The last administrator cannot be demoted or deleted. Without this the instance becomes permanently unadministrable, including the ability to grant admin.
- An administrator cannot delete their own account — it would drop them out of the only session that could undo it. Another administrator can.
- Deleting a user removes their `sync/<id>` and `backup/<id>` directories. Sessions cascade via the foreign key; files do not, and a later user allocated the same numeric id would otherwise inherit them.

## Passwords

- Minimum 8 characters, enforced server-side on every path that sets one.
- Changing your own password requires the current one and **signs out every device**, then issues one fresh token so the device that made the change stays signed in.
- An administrator reset issues a temporary password and revokes that user's sessions. The temporary password is returned exactly once and never stored recoverably — the UI shows it in a dialog that cannot be dismissed by tapping outside.
- **A wrong current password returns 422, not 401.** The auth middleware already uses 401 for "your session is gone"; sharing the status would leave the client unable to distinguish them, and it would pointlessly refresh its token and retry. Do not "fix" this back to 401.
- There is no forgotten-password flow, because there is no mail sending. An administrator resets it; if the only administrator is locked out, the operator runs `bin/create_user.dart <email>`, which now resets rather than failing.

## The first-run wizard

Launch order is **wizard → onboarding → app**, gated on `appStateSettings["hasCompletedServerSetup"]`.

- Native starts by asking for the server URL. Web skips that — it is served from its own API's origin, so `Uri.base.origin` is the answer — and goes straight to probing, with the field available behind an "advanced" disclosure for the case where that assumption is wrong.
- The probe result routes to **Set up this server** (`needsSetup: true`), **Sign in** (`false`), or **couldn't reach it** (`null`).

### Where it is mounted, and why it matters

In `main.dart`'s outermost `Stack`, above the `Row` that holds the sidebar — *not* inside `InitialPageRouteNavigator`, which sits in an `Expanded` beside `NavigationSidebar` and would leave the dimmed, inert sidebar visible next to the wizard. Equally not by replacing the `Row`, which would unmount `navigatorKey` and `snackbarKey` and turn `openSnackbar`, `popRoute` and `openLoadingPopupTryCatch` into live crashes.

Two consequences that are design constraints, not bugs:
- Snackbars posted while the wizard is up render *behind* it. **The wizard uses inline error text only.**
- `InitialPageRouteNavigator` renders an empty placeholder while the wizard is up, so `OnBoardingPage` does not mount underneath: its `initState` grabs focus and returns `KeyEventResult.handled` for every key, which would fight the wizard's text fields on the first frame.

### Local-first compliance

Non-negotiable, per `01-local-first-invariant.md`. A wizard before onboarding is the single most likely place for this project to accidentally make the app require a server.

| Requirement | Mechanism |
|---|---|
| Always skippable | "Use without an account" is built unconditionally in the wizard's `build`, outside the step switch, so no step can omit it |
| No blocking call to render | `build()` never awaits; the probe is launched from a `Future.microtask` or a button |
| Unreachable server tolerated | `selfHostedSetupState` returns `bool?` and swallows every exception → inline message, skip still present, nothing to dismiss |
| Bounded | 8s probe timeout, shorter than login's 15s because this is on the launch path |
| Cancel-safe | `if (!mounted) return;` after every await — the user can skip mid-probe |
| Re-enterable | The account page renders the same form, so someone who skipped gets the identical flow later |

**The wizard must never call `syncAfterLogin`.** `syncData` can reach `restartAppPopup` / `lockAppWaitForRestart`, which dims and disables the entire UI — unusable on a screen with no navigation, and a re-creation of the original complaint. `PageNavigationFramework` already runs `runAllCloudFunctions` on its first mount, so nothing is skipped by waiting.

### The upgrade migration is load-bearing

`getUserSettings()` merges every missing default key into stored settings on launch. A new `hasCompletedServerSetup: false` therefore reaches installs that onboarded long ago, and without `attemptToMigrateServerSetupWizard()` **every existing user would be dropped into a first-run wizard on update**. The migration back-fills `true` for anyone with `hasOnboarded`, `hasSignedIn`, or a live session, and — unlike the neighbouring `attemptToMigrate*` functions — persists immediately rather than relying on a later write. Covered by `app/test/server_setup_wizard_migration_test.dart`; do not delete those tests.

## Password managers

`autofillHints` is threaded through the app's `TextInput` widget to its `TextFormField`, and credential fields are wrapped in `AutofillGroup`. Before this, `grep -rn "autofillHints\|AutofillGroup" app/lib/` returned zero hits app-wide — managers could not see the fields at all.

Rules that are easy to break by accident:
- **Never give two fields in one `AutofillGroup` the same hint.** The web engine derives the DOM `id` and `name` from it, so a second `newPassword` field collides with the first. Confirm-password fields pass `null`.
- Use `AutofillHints.username`, not `.email` — `autocomplete="username"` is what login-form detection keys on, and only the first hint in the list reaches the web engine.
- The change-password sheet includes a read-only username field. Without one, most managers save a second orphaned entry instead of updating the existing one.
- `onDisposeAction: AutofillContextAction.cancel` on each group, with `finishAutofillContext(shouldSave: true)` called explicitly on success — the default fires the browser's save prompt even when the user backs out.

### What this actually delivers on web — do not overpromise

Verified against the engine shipped with Flutter 3.19.6, the version pinned in `/Dockerfile`:

- **Works:** hints become real `autocomplete`/`name`/`id` attributes; `AutofillGroup` makes the engine emit an actual `<form>`, which is what makes a browser treat the page as a login form at all; `finishAutofillContext` triggers the save prompt. Renderer-independent.
- **Does not:** nothing exists in the DOM until a field is focused. Built-in managers (Chrome, Safari/iCloud Keychain, Firefox) hook the focused input and work. **Extension-based managers — 1Password, Bitwarden, Dashlane — are unreliable**, often with no in-field badge; the user triggers fill from the extension's own UI. No app-side fix exists in this Flutter version.
- **The password visibility toggle cannot unmask on web.** The autofill hint is applied to the DOM element after `obscureText` and forces `type="password"`. The toggle is hidden behind `!kIsWeb` rather than shipped as a dead control — do not "restore" it.
- **HTTPS is required.** No browser offers password save or fill over plain `http://`. This is a deployment prerequisite, not an app bug.

Android native gets full autofill with none of these caveats.

## Known gaps, deliberately not addressed

- `POST /auth/login` has no rate limiting or lockout. Belongs with the Stage 3 hardening pass.
- `GET /auth/setup-state` discloses whether an instance has any users. Same as Immich and Nextcloud; accepted.
- Session tokens are stored in plain `sharedPreferences`, unchanged from Stage 1.

## Acceptance criteria

1. On a fresh instance (`docker compose down -v && up --build`) the wizard offers **Set up this server**; creating the account signs you in as administrator and lands in onboarding, then the app, **with a working, non-dimmed sidebar**. Test at a window wider than 700px, where the sidebar is visible — that is the exact path that used to deadlock.
2. Relaunching shows neither wizard nor onboarding, and stays signed in.
3. A second browser profile against the same instance is offered **Sign in**, not setup.
4. A password manager offers to save on sign-in and to fill later. Check Android and the iPhone PWA separately, with the web caveats above in mind.
5. Display name and password can both be changed; changing the password signs other devices out.
6. An administrator can add a second user, and that user can sign in elsewhere and is refused the admin section.
7. **The airplane-mode test from `01-local-first-invariant.md`, run against a fresh install**: with no network at all, the skip path reaches a fully usable app, transactions can be created, and they survive a relaunch.
8. **The upgrade test**: install the current release, complete onboarding, update to this build, and confirm the wizard does *not* appear. This is the highest-risk regression in the whole change.
