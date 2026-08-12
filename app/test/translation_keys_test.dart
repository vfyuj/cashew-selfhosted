import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one direction of translation-key drift that is always a bug: a
/// `.tr()` call whose key has no entry in en.json.
///
/// easy_localization does not fail on a missing key -- it logs, tries the
/// fallback, and then renders the raw key. So `"remain".tr()` on a screen
/// nobody opens during review ships as the literal text "remain" and stays
/// broken until a user reports it. Five keys were in exactly that state when
/// this test was written.
///
/// This lives in test/ rather than tool/ so CI catches it with no workflow
/// change -- `flutter test` already runs in .github/workflows/ci.yml.
void main() {
  // `"key".tr(` -- the only call shape this app uses. There is no
  // `context.tr()`, no generated LocaleKeys, and no interpolated key anywhere.
  final RegExp trCall = RegExp(r'"([^"\n]{1,80})"\s*\.tr\(');

  // Two kinds of string reach `.tr()`, and only one of them is a key:
  //
  //   "no-accounts-found".tr()      <- a key, must exist in en.json
  //   "Colorful Net Totals".tr()    <- a raw English debug label in
  //                                    lib/pages/debugPage.dart, deliberately
  //                                    absent from en.json and rendered by the
  //                                    missing-key passthrough
  //
  // Matching the kebab-case key shape separates them without an allowlist that
  // would need maintaining.
  final RegExp keyShaped = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  late Map<String, dynamic> english;
  late Map<String, List<String>> literalKeys;

  setUpAll(() {
    // `flutter test` runs with the package root as cwd, so these are the real
    // source files rather than a bundled asset snapshot.
    english = json.decode(
      File('assets/translations/generated/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    literalKeys = {};
    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || entity.path.endsWith('.dart') == false) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        // Commented-out code still contains `.tr()` calls that nothing runs.
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final RegExpMatch match in trCall.allMatches(lines[i])) {
          final String key = match.group(1)!;
          if (keyShaped.hasMatch(key) == false) continue;
          literalKeys.putIfAbsent(key, () => []).add('${entity.path}:${i + 1}');
        }
      }
    }
  });

  test('every translated key in lib/ exists in en.json', () {
    final Map<String, List<String>> missing = {
      for (final MapEntry<String, List<String>> entry in literalKeys.entries)
        if (english.containsKey(entry.key) == false) entry.key: entry.value,
    };

    expect(
      missing,
      isEmpty,
      reason: 'These keys are passed to .tr() but have no entry in '
          'assets/translations/generated/en.json, so they render as the raw '
          'key string:\n'
          '${missing.entries.map((e) => '  ${e.key}  (${e.value.join(', ')})').join('\n')}',
    );
  });

  test('reports keys in en.json that no literal call site uses', () {
    // Deliberately does not fail. Around 84 call sites translate a variable
    // holding a literal -- `getLabel: (item) => item.tr()` over a list of
    // strings -- which no regex over the source can see, so a chunk of this
    // list is always false positives. It is printed because the genuinely dead
    // upstream keys in it are worth noticing, not because it should gate CI.
    final List<String> orphans = english.keys
        .where((String key) => literalKeys.containsKey(key) == false)
        .toList()
      ..sort();

    print('${orphans.length} of ${english.length} en.json keys have no literal '
        '.tr() call site (expect false positives -- see the comment above).');
    expect(english, isNotEmpty);
  });
}
