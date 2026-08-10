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
///     the next `< ` line.
///   * any other non-empty line is one bullet, an empty line is a spacer.
///   * every line is indented four spaces, which the parser strips.
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
/// Empty for now. Upstream's entries were all `.tr()` keys resolved against
/// `assets/translations/generated/*.json`, which is machine-generated from an
/// upstream sheet this fork does not control (see
/// `specs/backlog/BL-003-upstream-legacy-translations-and-docs.md`), so they
/// could not simply be carried over. Add fork entries here with raw strings
/// when a release introduces something that deserves more than a bullet.
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
      } else if (string.trim() != "end") {
        changelogPoints.add(Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 5.5),
          child: TextFont(
            text: string,
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
