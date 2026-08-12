import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/translationOverrides.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The in-app translation editor rests on one assumption about
/// easy_localization: that an `extraAssetLoaders` entry is merged *after* the
/// bundle loader, so its entries win.
///
/// Nothing in the package's public API states that, and if a version bump
/// reversed the order, overrides would silently stop applying -- the app would
/// look completely normal and every edit would do nothing. That is the failure
/// this file exists to make loud. The pubspec pins easy_localization for the
/// same reason.
void main() {
  const AssetLoader bundleLoader = _FakeBundleLoader();
  const AssetLoader overrideLoader = TranslationOverrideAssetLoader();

  setUp(() {
    translationOverrides = {};
  });

  tearDown(() {
    translationOverrides = {};
  });

  test('an override wins over the bundled string for the same key', () async {
    translationOverrides = {
      "de": {"settings": "Meine Einstellungen"},
    };

    final Map<String, dynamic> merged = await _merge(
      [bundleLoader, overrideLoader],
      const Locale("de"),
    );

    expect(merged["settings"], "Meine Einstellungen");
    // Untouched keys still come from the bundle.
    expect(merged["cancel"], "Abbrechen");
  });

  test('a language with no overrides is left exactly as shipped', () async {
    translationOverrides = {
      "de": {"settings": "Meine Einstellungen"},
    };

    final Map<String, dynamic> merged = await _merge(
      [bundleLoader, overrideLoader],
      const Locale("fr"),
    );

    expect(merged["settings"], "Paramètres");
  });

  test('the loader returns null rather than throwing for any locale', () async {
    // The controller gathers loaders with Future.wait -- a throw there becomes
    // onLoadError, which replaces the whole app with an error screen.
    for (final Locale locale in <Locale>[
      ...supportedLocales.values,
      const Locale("ja"), // dropped from this fork
      const Locale("zz"), // never existed
    ]) {
      await expectLater(
        overrideLoader.load("assets/translations/generated", locale),
        completes,
      );
    }
  });

  test('overrides are keyed by language code, matching getLocalePath',
      () async {
    // getLocalePath maps any locale to `<languageCode>.json`, so the loader has
    // to bucket by the same thing or a system locale like fr_CA would get the
    // French file with nobody's overrides applied to it.
    translationOverrides = {
      "fr": {"settings": "Réglages"},
    };

    final Map<String, dynamic>? overrides = await overrideLoader.load(
      "assets/translations/generated",
      const Locale("fr", "CA"),
    );

    expect(overrides?["settings"], "Réglages");
    expect(
      const RootBundleAssetLoaderCustomLocaleLoader()
          .getLocalePath("assets/translations/generated", const Locale("fr", "CA")),
      "assets/translations/generated/fr.json",
    );
  });
}

/// Mirrors `EasyLocalizationController._combineAssetLoaders`: every loader is
/// awaited, then merged into one map in list order.
Future<Map<String, dynamic>> _merge(
    List<AssetLoader> loaders, Locale locale) async {
  final Map<String, dynamic> result = {};
  for (final AssetLoader loader in loaders) {
    final Map<String, dynamic>? loaded =
        await loader.load("assets/translations/generated", locale);
    if (loaded != null) result.addAll(loaded);
  }
  return result;
}

/// Stands in for the rootBundle loader so the test needs no asset bundle.
class _FakeBundleLoader extends AssetLoader {
  const _FakeBundleLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    const Map<String, Map<String, dynamic>> files = {
      "de": {"settings": "Einstellungen", "cancel": "Abbrechen"},
      "fr": {"settings": "Paramètres", "cancel": "Annuler"},
    };
    return files[locale.languageCode];
  }
}
