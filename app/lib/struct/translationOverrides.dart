import 'dart:convert';

import 'package:cashew_selfhosted/main.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';

/// User edits to the shipped translations, made in the in-app editor.
///
/// Shape is `localeKey -> translationKey -> value`, where localeKey is a key of
/// [supportedLocales]. Entries here win over the bundled asset for that
/// language; a key with no entry falls through to the file exactly as before.
///
/// This is deliberately *not* stored in `appStateSettings`. That map is
/// re-encoded whole on every settings write and is copied into Drift by
/// `backupSettings()`, where it rides the row-level sync feed -- a full locale's
/// worth of overrides is ~67 KB, and none of it belongs in either path.
/// Overrides stay on the device that made them; the editor's export/import is
/// how they move.
Map<String, Map<String, String>> translationOverrides = {};

const String _sharedPreferencesKey = "translationOverrides";
const String _translationsAssetPath = "assets/translations/generated";

/// Bumped on every change, so the editor can rebuild its row list without
/// diffing the map itself.
final ValueNotifier<int> translationOverridesVersion = ValueNotifier<int>(0);

/// Must run before `runApp`: the localization delegate loads on the first
/// frame, and [TranslationOverrideAssetLoader] reads this map directly.
/// Synchronous -- `sharedPreferences` is already resolved by this point -- so it
/// costs nothing at startup.
void loadTranslationOverrides() {
  try {
    final String? stored = sharedPreferences.getString(_sharedPreferencesKey);
    if (stored == null || stored.isEmpty) return;
    final Map<String, dynamic> decoded =
        json.decode(stored) as Map<String, dynamic>;
    translationOverrides = {
      for (final MapEntry<String, dynamic> entry in decoded.entries)
        entry.key: {
          for (final MapEntry<String, dynamic> override
              in (entry.value as Map<String, dynamic>).entries)
            override.key: override.value.toString(),
        },
    };
  } catch (e) {
    // A corrupt blob must not take the app down before it has drawn a frame.
    // Shipped translations are a complete, working set on their own.
    print("Error loading translation overrides " + e.toString());
    translationOverrides = {};
  }
}

Future<void> persistTranslationOverrides() async {
  translationOverrides.removeWhere(
      (String _, Map<String, String> overrides) => overrides.isEmpty);
  await sharedPreferences.setString(
      _sharedPreferencesKey, json.encode(translationOverrides));
  translationOverridesVersion.value++;
}

/// Sets one string for one language. A null, empty or whitespace-only [value]
/// removes the override instead of storing it -- an empty translation renders
/// as an empty label with no visible way back, since
/// `useFallbackTranslationsForEmptyResources` is false.
Future<void> setTranslationOverride(
    String localeKey, String key, String? value) async {
  if (value == null || value.trim().isEmpty) {
    translationOverrides[localeKey]?.remove(key);
  } else {
    translationOverrides.putIfAbsent(localeKey, () => {})[key] = value;
  }
  await persistTranslationOverrides();
}

Future<void> clearTranslationOverridesForLocale(String localeKey) async {
  translationOverrides.remove(localeKey);
  await persistTranslationOverrides();
}

Future<void> clearAllTranslationOverrides() async {
  translationOverrides.clear();
  await persistTranslationOverrides();
}

/// Merges [translationOverrides] on top of whatever the bundled asset says.
///
/// Registered as an `extraAssetLoaders` entry rather than by subclassing the
/// bundle loader: easy_localization builds `[assetLoader, ...extraAssetLoaders]`
/// and merges their results in order, so entries returned here already win.
///
/// Must never throw. The controller gathers loaders with `Future.wait`, and an
/// exception there becomes `onLoadError` -- which replaces the entire app with
/// an error screen.
class TranslationOverrideAssetLoader extends AssetLoader {
  const TranslationOverrideAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    return translationOverrides[locale.languageCode];
  }
}

/// The shipped strings for one language, with overrides applied.
Future<Map<String, dynamic>> bundledTranslationsWithOverrides(
    Locale locale) async {
  final Map<String, dynamic> bundled = await bundledTranslations(locale);
  final Map<String, String>? overrides =
      translationOverrides[locale.languageCode];
  if (overrides == null || overrides.isEmpty) return bundled;
  return Map<String, dynamic>.from(bundled)..addAll(overrides);
}

/// The shipped strings for one language, exactly as they ship. This is what the
/// editor shows as the untouched value, and what "revert" restores to.
///
/// `rootBundle` caches decoded strings, so repeated calls are cheap.
Future<Map<String, dynamic>> bundledTranslations(Locale locale) async {
  final String assetPath =
      const RootBundleAssetLoaderCustomLocaleLoader().getLocalePath(
    _translationsAssetPath,
    locale,
  );
  return json.decode(await rootBundle.loadString(assetPath))
      as Map<String, dynamic>;
}

/// Applies an override to the running app without a restart.
///
/// The obvious routes do not work. `context.setLocale(context.locale)` is
/// guarded to a no-op when the locale is unchanged, and `context.resetLocale()`
/// reloads the controller but leaves `updateShouldNotify` false, so MaterialApp
/// never rebuilds and the delegate never re-runs. Meanwhile all ~1800 call
/// sites are `"key".tr()` with no BuildContext, which resolve against the
/// [Localization] singleton.
///
/// So we replace the singleton's maps directly. `Localization.load` is the same
/// public static the package's own delegate calls; the arguments below mirror
/// what the controller assembles, which is why the pubspec pins the version.
Future<void> applyTranslationOverridesNow(BuildContext context) async {
  final Locale locale = context.locale;
  Localization.load(
    locale,
    translations: Translations(await bundledTranslationsWithOverrides(locale)),
    // Every supported locale is a bare language code, so the controller's
    // country-code base-language overlay never applies -- English alone is the
    // fallback. Overrides matter here too: an edit to an English string is what
    // reaches the keys that no other language file defines.
    fallbackTranslations: Translations(
        await bundledTranslationsWithOverrides(supportedLocales["en"]!)),
    // Both must match InitializeLocalizations, which takes the package defaults.
    useFallbackTranslationsForEmptyResources: false,
    ignorePluralRules: true,
  );
  appStateKey.currentState?.refreshAppState();
  refreshPageFrameworks();
}
