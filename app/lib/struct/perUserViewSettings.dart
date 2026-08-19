import 'dart:convert';

import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';

// How one household member wants their own screens arranged, kept separate
// from the other member's and carried between that member's own devices.
//
// STORAGE: the `AppSettings` table, one row per member, keyed by their server
// user id.
//
//   row 0        -> the whole sharedPreferences blob written by
//                   backupSettings(). Device-local, never synced, unchanged.
//   row <userId> -> that member's view preferences, and only the keys in
//                   [syncedViewSettingKeys].
//
// Row 0 is excluded from the change feed by getAllNewAppSettings, and that
// exclusion is the safety property that makes syncing this table acceptable at
// all: row 0 carries the server URL and the signed-in email, neither of which
// should travel.
//
// WHY NOT sharedPreferences: it is per device, so a member's phone and laptop
// would never agree. WHY NOT a column on Wallets: Wallets has no dead column
// to borrow, unlike Budgets, so it would be the first deliberate break of the
// schema-identical-to-upstream invariant (CLAUDE.md). A row in a table that
// already exists costs neither.

/// The settings that follow a member between their own devices.
///
/// Deliberately a short allow-list rather than the whole settings map. Most of
/// `appStateSettings` is either device-local (the server URL, which platform's
/// icons to draw) or account-wide, and syncing it wholesale would move all of
/// that too. Adding a key here is a decision to make it follow the person;
/// make it one at a time.
///
/// Note what does *not* belong here even though it once looked like it did:
/// the currency table. It has to be the same for everyone rather than follow
/// one person, and this mechanism has no household-wide level -- so it lives
/// on the server instead. See docs/server/rates.md.
const List<String> syncedViewSettingKeys = [
  // Wallets this member has hidden from their own home page. See
  // [hiddenWalletPks].
  'hiddenWalletPks',
  // Which sections the home page shows, and in what order.
  'homePageOrder',
  'homePageOrderFullScreen',
  'showWalletSwitcher',
  'showWalletList',
  // Which account this member is looking at.
  'selectedWalletPk',
];

/// The settings row belonging to the signed-in member, or null when signed out
/// or on a solo account.
///
/// Solo accounts are excluded on purpose: with nobody to differ from, a synced
/// row would be pure overhead, and it would start being pushed the moment a
/// second member joined without anyone having asked for it.
int? get _currentSettingsRowPk {
  final ServerProfile? profile = cachedServerProfile;
  if (profile == null || profile.id <= 0) return null;
  if (!profile.sharesHousehold) return null;
  return profile.id;
}

/// Whether this device is in a position to keep per-user view settings.
bool get perUserViewSettingsApply => _currentSettingsRowPk != null;

/// The settings row this device may keep after a restore, if any.
int? get currentViewSettingsRowPk => _currentSettingsRowPk;

/// True while [applyStoredViewSettings] is writing pulled values back into
/// [appStateSettings].
///
/// updateSettings mirrors every allow-listed key into this member's row, which
/// is right when a person changes something and wrong when the change came
/// from their other device: the keys are applied one at a time, so each write
/// would store a half-applied mixture under a fresh timestamp and push it
/// back. It settles on its own -- the second device finds nothing to change
/// and stops -- but it is a pointless round trip, so it is suppressed instead.
bool _applyingStoredViewSettings = false;

/// Reads this member's stored view preferences into [appStateSettings].
///
/// Called after a sync cycle applies changes, so a preference changed on this
/// member's other device shows up here. Returns whether anything changed.
Future<bool> applyStoredViewSettings() async {
  final int? pk = _currentSettingsRowPk;
  if (pk == null) return false;

  final AppSetting? row = await database.getSettingsRowOrNull(pk);
  if (row == null) return false;

  Map<String, dynamic> stored;
  try {
    final dynamic decoded = json.decode(row.settingsJSON);
    if (decoded is! Map<String, dynamic>) return false;
    stored = decoded;
  } catch (e) {
    // A malformed row must not stop the app from starting or a sync from
    // completing -- these are screen preferences, not data.
    print("Could not read stored view settings: $e");
    return false;
  }

  bool changed = false;
  _applyingStoredViewSettings = true;
  try {
    for (String key in syncedViewSettingKeys) {
      if (!stored.containsKey(key)) continue;
      // Compared as encoded JSON: these values include lists, and two equal
      // lists are not `==` in Dart, so a plain comparison would report every
      // list-valued preference as changed on every sync.
      if (json.encode(appStateSettings[key]) == json.encode(stored[key])) {
        continue;
      }
      await updateSettings(key, stored[key],
          updateGlobalState: false, pagesNeedingRefresh: [0]);
      changed = true;
    }
  } finally {
    _applyingStoredViewSettings = false;
  }
  return changed;
}

/// Writes this member's current view preferences to their row, so their other
/// devices pick them up.
///
/// A no-op when nothing in the allow-list has actually changed, so this can be
/// called freely from settings writes without generating sync traffic.
Future<void> storeViewSettings() async {
  if (_applyingStoredViewSettings) return;
  final int? pk = _currentSettingsRowPk;
  if (pk == null) return;

  final Map<String, dynamic> current = {
    for (String key in syncedViewSettingKeys)
      if (appStateSettings.containsKey(key)) key: appStateSettings[key]
  };
  final String encoded = json.encode(current);

  final AppSetting? existing = await database.getSettingsRowOrNull(pk);
  if (existing != null && existing.settingsJSON == encoded) return;

  await database.createOrUpdateSettings(AppSetting(
    settingsPk: pk,
    settingsJSON: encoded,
    dateUpdated: DateTime.now(),
  ));
}

/// Wallets this member has hidden from their own home page.
///
/// Layered on top of `Wallets.homePageWidgetDisplay` rather than replacing it:
/// that column stays the household's shared decision about which accounts are
/// pinned where, and this removes some of them from one person's view. Additive,
/// so every existing query keeps its meaning.
Set<String> get hiddenWalletPks {
  final dynamic stored = appStateSettings["hiddenWalletPks"];
  if (stored is! List) return const {};
  return stored.whereType<String>().toSet();
}

bool isWalletHiddenForCurrentUser(String walletPk) =>
    hiddenWalletPks.contains(walletPk);

/// Hides or shows [walletPk] on this member's own home page.
Future<void> setWalletHiddenForCurrentUser(String walletPk, bool hidden) async {
  final Set<String> next = Set<String>.from(hiddenWalletPks);
  if (hidden) {
    next.add(walletPk);
  } else {
    next.remove(walletPk);
  }
  // updateSettings mirrors allow-listed keys into this member's row itself,
  // so there is nothing to store explicitly here.
  await updateSettings("hiddenWalletPks", next.toList(),
      updateGlobalState: false, pagesNeedingRefresh: [0]);
}
