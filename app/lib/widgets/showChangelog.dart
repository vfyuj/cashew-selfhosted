import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/outlinedButtonStacked.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'listItem.dart';

/// The upstream Cashew release this fork was branched from.
///
/// Kept as a constant because `pubspec.yaml` no longer records it: the fork
/// restarted version numbering at 1.0.0-beta.1 and does not continue the 5.x
/// line. Shown on the About page so the lineage isn't lost, and it's the
/// number to quote when diffing against `upstream/`.
const String upstreamBaseVersion = "5.4.3";

// Device legend
// Apple rejected app update because Android was referenced... We use code names now!
// (i) = iOS
// (A) = Android

/// This fork's changelog, newest section first.
///
/// Format (inherited from upstream Cashew, parsed by
/// [getChangelogPointsWidgets]):
///   * a line starting with `< ` opens the section for that version and is
///     rendered as its heading; every line below belongs to that version until
///     the next `< ` line. Version numbers are not translated.
///   * a line starting with `## ` is a short bold title for the feature
///     described by the paragraph(s) that follow it, so a version with
///     several unrelated changes reads as scannable sections instead of a
///     wall of paragraphs. Use one whenever a version has more than one
///     feature worth separating; skip it for a version that is just a single
///     bug fix, where the version heading already says everything a title
///     would.
///   * any other non-empty line is one bullet, an empty line is a spacer.
///   * every line is indented four spaces, which the parser strips.
///
/// Title and bullet lines are `.tr()` keys, not raw English: both are passed
/// through `.tr()` when rendered, so put a `changelog-<version>-<feature>-title`
/// / `-body` key here and add the actual English/translated text to all 8
/// `assets/translations/generated/<locale>.json` files (same rule as every
/// other piece of user-facing text -- see CLAUDE.md § Translations). This
/// used to be an explicit exception (raw English, never `.tr()`) because the
/// translations pipeline was upstream-owned and couldn't safely take new
/// fork keys; that blocker is gone as of BL-007, so the exception no longer
/// applies here. It still applies to the translation editor's own chrome
/// (`translationEditorPage.dart`), which has a real, separate reason to stay
/// untranslated: it's the tool you'd use to fix a broken translation, so it
/// can't depend on the system it exists to repair.
///
/// Older sections below predate this rule and are still raw English rather
/// than keys. That's fine: `.tr()` on a string with no matching key falls
/// back to rendering the string itself, which is exactly the old behaviour --
/// no need to backfill keys for a version nobody's looking at, only for new
/// ones.
///
/// A section is only shown when its version is newer than the last version the
/// user launched, so a beta with no section of its own produces no popup at
/// all. That is deliberate: `.githooks/pre-commit` bumps the version on every
/// commit, but only changes worth interrupting someone for earn an entry here.
///
/// Upstream Cashew's own changelog used to live here and was removed when the
/// fork started numbering its own releases. It is still readable verbatim in
/// the read-only clone at `upstream/budget/lib/widgets/showChangelog.dart`.
String getChangelogString() {
  return """
    < 1.3.0
    ## changelog-1-3-0-envelope-sync-title
    changelog-1-3-0-envelope-sync-body
    ## changelog-1-3-0-envelope-page-title
    changelog-1-3-0-envelope-page-body
    ## changelog-1-3-0-envelope-order-title
    changelog-1-3-0-envelope-order-body

    < 1.2.1
    changelog-1-2-1-envelope-currency-body

    < 1.2.0
    ## changelog-1-2-0-envelopes-title
    changelog-1-2-0-envelopes-body
    ## changelog-1-2-0-budgets-title
    changelog-1-2-0-budgets-body

    < 1.1.1
    changelog-1-1-1-category-transactions-body

    < 1.1.0
    ## changelog-1-1-0-date-time-picker-title
    changelog-1-1-0-date-time-picker-body
    ## changelog-1-1-0-backup-naming-title
    changelog-1-1-0-backup-naming-body
    ## changelog-1-1-0-wallet-visibility-title
    changelog-1-1-0-wallet-visibility-body

    < 1.0.4
    ## changelog-1-0-4-subcategory-colors-title
    changelog-1-0-4-subcategory-colors-body
    ## changelog-1-0-4-account-dedupe-title
    changelog-1-0-4-account-dedupe-body

    < 1.0.3
    ## changelog-1-0-3-shared-budgets-title
    changelog-1-0-3-shared-budgets-body
    ## changelog-1-0-3-subcategory-budgets-title
    changelog-1-0-3-subcategory-budgets-body
    ## changelog-1-0-3-personal-budgets-title
    changelog-1-0-3-personal-budgets-body
    ## changelog-1-0-3-overspending-warnings-title
    changelog-1-0-3-overspending-warnings-body
    ## changelog-1-0-3-hide-accounts-title
    changelog-1-0-3-hide-accounts-body
    ## changelog-1-0-3-sharing-semantics-title
    changelog-1-0-3-sharing-semantics-body

    < 1.0.2
    Translations no longer depend on anything outside this app. You can now fix any piece of text yourself: Settings, Language, Edit translations. Search for it, type the fix, and it applies immediately - no restart.
    Russian has been rewritten from scratch to match this app, not the original Cashew it was translated from.
    The app now ships 8 languages instead of 46. The other 38 were never updated for this fork and were quietly showing English or a stale sentence about Google Drive. Missing one? Translate it yourself in Settings, and it can be added back.

    < 1.0.1
    Fixes a crash opening the Budgets tab on iPhone after a database import, caused by iOS Safari getting a different, less stable renderer than every other device.

    < 1.0.0
    Cashew Selfhosted reaches 1.0.0. It's the Cashew you know, running entirely on your own server - no Google account, nothing leaving your network. A backup exported from the original Cashew still imports here, unchanged.
    Your devices stay constantly synced while online. Change something on your phone and your laptop catches up on its own.
    The Home and Budgets pages show Monthly Cash Flow: what you expect to come in and what you've planned to spend, side by side, so you can see whether the month fits before you're in it.
    The app still works completely offline.

    < 1.0.0-beta.22
    Changing a budget's amount now applies from the current period onward only. Periods that have already ended keep the amount they were set to at the time, so your budget history stops rewriting itself every time you adjust a target.
    This covers every main category budget and every custom budget. Spending goals set for individual categories inside a budget still use one amount for all periods.
    Changing a budget's cycle - how often it repeats, how long a period is, or when it starts - clears its saved history, because the old period boundaries no longer line up. Cashew asks before doing that.

    < 1.0.0-beta.20
    The Home and Budgets pages now show Monthly Cash Flow instead of Planned vs. Actual: income and expenses as two separate, readable figures instead of one net number nobody could reconstruct on sight.
    Settings is reorganized into grouped cards and now follows your Material You accent colour, with a colour swatch on the Accent Color row so you can see what's set without opening the picker.
    The "changes were overwritten by another device" message is gone from ordinary syncing. It only ever meant last-write-wins doing its job, not lost data.

    < 1.0.0-beta.12
    Every remaining Google dependency is gone. The app no longer contacts Google at all, on any screen, at any point.
    Receipt attachments now upload to your own server instead of Google Drive. Attachments you added before this update keep their old Drive links and still open, but only new ones get the in-app preview.
    Everything is unlocked. The upstream paywall on budgets, goals, past budgets and custom colours has been removed.
    Removed with it: shared budgets, Gmail receipt scanning, Google Sheets import, and the feedback and app-rating prompts.
    Scanning transactions from Android notifications is unaffected, along with importing a CSV file.

    < 1.0.0-beta.1
    Cashew Selfhosted now has its own version number, starting over at 1.0.0-beta.1. It no longer follows upstream Cashew's 5.x releases.
    The version is shown in the sidebar, so you can tell at a glance whether a redeploy actually reached your browser.
    This changelog now covers only this fork's changes.

    What the fork changed before it started numbering releases:
    Google Sign-In, Firebase and Google Drive are gone. You sign in to an account on your own server instead.
    Sync and backup are handled by that server, with an optional WebDAV/Nextcloud target for backups.
    A first-run setup wizard creates the first account, which becomes the instance administrator.
    Your name, email and password can be changed in the app, and administrators can create further accounts.
    The app still works fully offline. Signing in is never required to use it.
    Based on upstream Cashew $upstreamBaseVersion, with an unchanged database layout, so an original Cashew backup still imports.
""";
}

/// Highlighted, tappable "major change" cards shown above the plain changelog
/// bullets for a given version.
///
/// Empty for now -- upstream's entries didn't carry over when this fork
/// stopped following upstream's changelog. `MajorChanges.title` is passed to
/// `.tr()` (see `getAllMajorChangeWidgetsForVersion`), so a fork entry here
/// follows the same rule as the plain bullets above: a translation key with
/// matching entries in all 8 locale files, not raw English.
Map<String, List<MajorChanges>> getMajorChanges() {
  return {};
}

bool showChangelog(
  BuildContext context, {
  bool forceShow = false,
  bool majorChangesOnly = false,
  Widget? extraWidget,
}) {
  String version = packageInfoGlobal?.version ?? "";

  // Upstream gated the full changelog on an English locale, falling back to
  // major-changes-only elsewhere, because the bullets are untranslated. This
  // fork's major-changes map is empty, so that gate would mean "no changelog
  // at all outside English". Untranslated English beats nothing here.
  List<Widget>? changelogPoints = getChangelogPointsWidgets(
    context,
    forceShow: forceShow,
    majorChangesOnly: majorChangesOnly,
  );

  updateSettings(
    "lastLoginVersion",
    version,
    pagesNeedingRefresh: [],
    updateGlobalState: false,
  );

  //Don't show changelog on first login
  if (changelogPoints != null &&
      changelogPoints.length > 0 &&
      (forceShow || appStateSettings["numLogins"] > 1)) {
    openBottomSheet(
      context,
      PopupFramework(
        title: "changelog".tr(),
        subtitle: getVersionString(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [(extraWidget ?? SizedBox.shrink()), ...changelogPoints],
        ),
        showCloseButton: true,
      ),
      showScrollbar: true,
    );
    return true;
  }
  return false;
}

List<Widget>? getChangelogPointsWidgets(BuildContext context,
    {bool forceShow = false, bool majorChangesOnly = false}) {
  String changelog = getChangelogString();
  Map<String, List<MajorChanges>> majorChanges = getMajorChanges();
  String version = packageInfoGlobal?.version ?? "";
  int versionInt = parseVersionInt(version);
  int lastLoginVersionInt =
      parseVersionInt(appStateSettings["lastLoginVersion"]);

  // A stored version newer than the running one means the saved value belongs
  // to a different lineage or a downgrade, and comparing against it would hide
  // every section forever. It is what an install carried over from upstream
  // Cashew looks like: "5.4.3" outranks every 1.x this fork will ever ship.
  // Treat it as "nothing seen yet" so the changelog shows once.
  if (lastLoginVersionInt > versionInt) {
    lastLoginVersionInt = 0;
  }

  if (forceShow || lastLoginVersionInt != versionInt) {
    List<Widget> changelogPoints = [];
    List<Widget> majorChangelogPointsAtTop = [];

    int versionBookmark = versionInt;
    for (String string in changelog.split("\n")) {
      string = string.replaceFirst("    ", ""); // remove the indent

      // Skip android changes on iOS, skip iOS changes on Android
      if (getPlatform() == PlatformOS.isIOS && string.contains(("(A)"))) {
        continue;
      } else if (getPlatform() == PlatformOS.isAndroid &&
          string.contains(("(i)"))) {
        continue;
      }
      string = string.replaceAll("(A)", "Android");
      string = string.replaceAll("(i)", "iOS");

      if (string.startsWith("< ")) {
        if (forceShow) {
          changelogPoints.addAll(getAllMajorChangeWidgetsForVersion(
                  context, string, majorChanges) ??
              []);
        }

        versionBookmark = parseVersionInt(string.replaceAll("< ", ""));
        if (forceShow == false && versionBookmark <= lastLoginVersionInt) {
          continue;
        }

        majorChangelogPointsAtTop.addAll(
            getAllMajorChangeWidgetsForVersion(context, string, majorChanges) ??
                []);

        if (majorChangesOnly == true) {
          continue;
        }

        changelogPoints.add(Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 5, top: 3),
          child: TextFont(
            text: string.replaceAll("< ", ""),
            fontSize: 25,
            maxLines: 10,
            fontWeight: FontWeight.bold,
          ),
        ));
        continue;
      }

      if (majorChangesOnly == true) {
        continue;
      }

      if (forceShow == false && versionBookmark <= lastLoginVersionInt) {
        continue;
      }

      if (string.trim() == "") {
        // this is an empty line
        changelogPoints.add(SizedBox(
          height: 8,
        ));
      } else if (string.startsWith("## ")) {
        // a short title for the feature described by the paragraph(s) below it
        changelogPoints.add(Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 2, top: 8),
          child: TextFont(
            text: string.replaceFirst("## ", "").tr(),
            fontSize: 17,
            maxLines: 3,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (string.trim() != "end") {
        changelogPoints.add(Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 5.5),
          child: TextFont(
            text: string.tr(),
            fontSize: 16.5,
            maxLines: 5,
          ),
        ));
      }
    }
    if (changelogPoints.length > 0)
      changelogPoints.add(
        SizedBox(height: 10),
      );

    if (!forceShow) changelogPoints.insertAll(0, majorChangelogPointsAtTop);
    return changelogPoints;
  }
  return null;
}

/// A comparable integer for a version string like "1.0.0-beta.12" or "1.0.0",
/// ordered the way semver says: 1.0.0-beta.1 < 1.0.0-beta.2 < 1.0.0 < 1.0.1.
/// A release therefore sorts above every pre-release of the same
/// major.minor.patch.
///
/// This replaced a version that stripped the dots and called `int.parse` on
/// what was left. That worked for upstream's plain "5.4.3" but throws on any
/// pre-release suffix, and the catch returned 0 -- which would have silently
/// disabled the changelog entirely once this fork moved to 1.0.0-beta.N.
///
/// Returns 0 for anything unparseable, including "", which is what
/// `lastLoginVersion` holds on a fresh install.
int parseVersionInt(String versionString) {
  final RegExpMatch? match =
      RegExp(r"^(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z]+\.?(\d+))?")
          .firstMatch(versionString.trim());
  if (match == null) return 0;

  final int major = int.parse(match.group(1)!);
  final int minor = int.parse(match.group(2)!);
  final int patch = int.parse(match.group(3)!);
  // No pre-release means a final release, which outranks every pre-release of
  // the same patch. 99999 also caps the usable beta counter at 99998, which is
  // roughly 99998 commits more than this fork needs before 1.0.0.
  final int preRelease =
      match.group(4) == null ? 99999 : int.parse(match.group(4)!);

  // Tops out around 1e12 even for an absurd 9999.999.999, well inside the
  // range Dart ints keep exact on the web (2^53).
  return ((major * 1000 + minor) * 1000 + patch) * 100000 + preRelease;
}

/// The long form, for the About page and bug reports: "v1.0.0-beta.12+12, db-v46".
String getVersionString() {
  String version = packageInfoGlobal?.version ?? "";
  String buildNumber = packageInfoGlobal?.buildNumber ?? "";
  return "v" +
      version +
      "+" +
      buildNumber +
      ", db-v" +
      schemaVersionGlobal.toString();
}

/// The short form for the navigation sidebar: "v1.0.0-beta.12". Drops the build
/// number (it tracks the beta counter anyway) and the database schema version,
/// neither of which earns the width in a nav row.
String getVersionStringShort() {
  return "v" + (packageInfoGlobal?.version ?? "");
}

class MajorChanges {
  MajorChanges(this.title, this.icon, {this.info, this.onTap});

  String title;
  IconData icon;
  List<String>? info;
  Function(BuildContext context)? onTap;
}

List<Widget>? getAllMajorChangeWidgetsForVersion(BuildContext context,
    String version, Map<String, List<MajorChanges>> majorChanges) {
  if (majorChanges[version] == null) return null;
  return [
    SizedBox(height: 5),
    for (MajorChanges majorChange in (majorChanges[version] ?? []))
      Padding(
        padding: const EdgeInsetsDirectional.only(
          bottom: 5,
          top: 5,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButtonStacked(
                filled: false,
                alignStart: true,
                alignBeside: true,
                padding: EdgeInsetsDirectional.symmetric(
                    horizontal: 20, vertical: 20),
                text: majorChange.title.tr(),
                iconData: majorChange.icon,
                onTap: majorChange.onTap == null
                    ? null
                    : () => majorChange.onTap!(context),
                afterWidget: majorChange.info == null
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (String info in majorChange.info ?? [])
                            ListItem(
                              info.tr(),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    SizedBox(height: 10),
  ];
}
