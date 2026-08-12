import 'dart:convert';

import 'package:cashew_selfhosted/struct/translationOverrides.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String globalAppName = "Cashew";

Map<String, dynamic> languageNamesJSON = {};
loadLanguageNamesJSON() async {
  languageNamesJSON = await json
      .decode(await rootBundle.loadString('assets/static/language-names.json'));
}

// The languages this fork ships, and the only files that may exist in
// assets/translations/generated/. See assets/translations/README.md for why the
// list is this short: these files are no longer generated from upstream's
// spreadsheet, they are maintained here, and a language nobody maintains is a
// language that quietly lies to whoever picks it.
//
// Every entry is a bare language code on purpose. Script/country variants
// (upstream had zh_Hant and pt_PT) would resurrect the special-casing that
// getLocalePath used to carry -- and that special-casing had a real bug, see
// RootBundleAssetLoaderCustomLocaleLoader below.
//
// Adding a language back is two steps: restore its file from git history
// (`git show <commit>:app/assets/translations/generated/xx.json`) and add a row
// here.
Map<String, Locale> supportedLocales = {
  "en": Locale("en"),
  "ru": Locale("ru"),
  "de": Locale("de"),
  "es": Locale("es"),
  "fr": Locale("fr"),
  "pt": Locale("pt"),
  "uk": Locale("uk"),
  "zh": Locale("zh"),
};

// In Material App to debug:
// localeListResolutionCallback: (systemLocales, supportedLocales) {
//   print("LOCALE:" + context.locale.toString());
//   print("LOCALE:" + Platform.localeName);
//   return null;
// },

/// Maps any locale to the one file that can serve it.
///
/// Every file in assets/translations/generated/ is named for a bare language
/// code, so the country/script subtags are dropped here. That is safe for a
/// locale easy_localization asks us about -- `selectLocaleFrom` always resolves
/// to a member of [supportedLocales] before the delegate loads anything -- and
/// it also keeps a system locale like `fr_CA` or `zh_Hant` from asking for a
/// file that does not exist.
///
/// This used to special-case zh_Hant and pt_PT by reading
/// `appStateSettings["locale"]`. That branch fired on the *fallback* load too:
/// with `useFallbackTranslations: true` the controller loads `en` through this
/// same method, so those users got their own language back as their "English"
/// fallback, and every key missing from it rendered as a raw key string rather
/// than English. Dropping both variants removed the branch and the bug with it.
///
/// This implements `EasyLocalization(useOnlyLangCode: true, ...)`, which is why
/// `useOnlyLangCode` stays false: only RootBundleAssetLoader consults it, and we
/// have replaced that logic. Locale *support* checks are unaffected -- they
/// compare language codes, so a system `fr_CA` still matches our `fr`.
class RootBundleAssetLoaderCustomLocaleLoader extends RootBundleAssetLoader {
  const RootBundleAssetLoaderCustomLocaleLoader();

  @override
  String getLocalePath(String basePath, Locale locale) {
    return '$basePath/${locale.languageCode}.json';
  }
}

class InitializeLocalizations extends StatelessWidget {
  const InitializeLocalizations({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      useOnlyLangCode: false,
      assetLoader: RootBundleAssetLoaderCustomLocaleLoader(),
      // Merged after the bundle loader and therefore wins, which is how a
      // string edited in the in-app editor survives a restart and a locale
      // switch without touching any of the ~1800 .tr() call sites.
      extraAssetLoaders: const [TranslationOverrideAssetLoader()],
      supportedLocales: supportedLocales.values.toList(),
      path: 'assets/translations/generated',
      useFallbackTranslations: true,
      // Named rather than `.values.first`, which was only correct because Dart
      // map literals happen to preserve insertion order.
      fallbackLocale: supportedLocales["en"]!,
      child: child,
    );
  }
}

// Language names can be found in
// /budget/assets/static/language-names.json
