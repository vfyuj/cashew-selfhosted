// Merges a translation-overrides export from the in-app editor into the
// shipped language files, so an edit made on one device becomes what everyone
// gets in the next build.
//
//   dart run tool/merge_translation_overrides.dart <export.json> [options]
//
//     --dry-run          Report what would change; write nothing.
//     --locale <code>    Only this language (repeatable).
//
// Plain Dart -- dart:io and dart:convert only -- so it runs without the Flutter
// toolchain, like server/bin/create_user.dart.
//
// The output has to be byte-identical to what the files already look like
// wherever nothing changed, or every promotion produces a diff touching all
// 1300 lines. That means two-space indent, literal non-ASCII, no trailing
// newline. `dart run tool/merge_translation_overrides.dart --self-test` proves
// it against the real files before anything is written.

import 'dart:convert';
import 'dart:io';

const String expectedFormat = "cashew-selfhosted-translation-overrides";
const String translationsDirectory = "assets/translations/generated";

/// Same rule as `RootBundleAssetLoaderCustomLocaleLoader.getLocalePath` in the
/// app: every file is named for a bare language code.
String fileNameForLocale(String localeKey) =>
    "${localeKey.replaceAll("_", "-")}.json";

final JsonEncoder _encoder = const JsonEncoder.withIndent("  ");

String encodeTranslations(Map<String, dynamic> translations) =>
    _encoder.convert(translations);

void main(List<String> arguments) {
  if (arguments.contains("--self-test")) {
    exit(runSelfTest() ? 0 : 1);
  }

  final bool dryRun = arguments.contains("--dry-run");
  final List<String> onlyLocales = [];
  String? exportPath;

  for (int i = 0; i < arguments.length; i++) {
    final String argument = arguments[i];
    if (argument == "--locale") {
      if (i + 1 >= arguments.length) {
        stderr.writeln("--locale needs a language code");
        exit(2);
      }
      onlyLocales.add(arguments[++i]);
    } else if (argument.startsWith("--")) {
      continue;
    } else {
      exportPath = argument;
    }
  }

  if (exportPath == null) {
    stderr.writeln(
        "usage: dart run tool/merge_translation_overrides.dart <export.json> "
        "[--dry-run] [--locale <code>]");
    exit(2);
  }

  final File exportFile = File(exportPath);
  if (exportFile.existsSync() == false) {
    stderr.writeln("No such file: $exportPath");
    exit(2);
  }

  final Map<String, dynamic> export =
      json.decode(exportFile.readAsStringSync()) as Map<String, dynamic>;
  if (export["format"] != expectedFormat) {
    stderr.writeln("Not a translations export -- expected "
        '"format": "$expectedFormat", got ${export["format"]}.');
    exit(2);
  }

  final Map<String, dynamic> overrides =
      (export["overrides"] as Map<String, dynamic>?) ?? {};
  if (overrides.isEmpty) {
    stdout.writeln("Export contains no overrides. Nothing to do.");
    return;
  }

  int totalChanged = 0;
  int totalAdded = 0;
  int filesWritten = 0;

  for (final MapEntry<String, dynamic> localeEntry in overrides.entries) {
    final String localeKey = localeEntry.key;
    if (onlyLocales.isNotEmpty && onlyLocales.contains(localeKey) == false) {
      continue;
    }

    // Only files this export actually mentions are opened, let alone rewritten.
    final File file =
        File("$translationsDirectory/${fileNameForLocale(localeKey)}");
    if (file.existsSync() == false) {
      stderr.writeln("! $localeKey -- ${file.path} does not exist. This fork "
          "ships a short list of languages; add the file and a row in "
          "lib/struct/languageMap.dart first.");
      continue;
    }

    final String before = file.readAsStringSync();
    final Map<String, dynamic> translations =
        json.decode(before) as Map<String, dynamic>;

    final List<String> changed = [];
    final List<String> added = [];
    (localeEntry.value as Map<String, dynamic>)
        .forEach((String key, dynamic value) {
      final String text = value.toString();
      if (translations.containsKey(key) == false) {
        added.add(key);
      } else if (translations[key] != text) {
        changed.add(key);
      } else {
        return;
      }
      // Dart maps preserve insertion order, so an existing key keeps its
      // position and a new one lands at the end -- the diff stays to the lines
      // that actually changed.
      translations[key] = text;
    });

    if (changed.isEmpty && added.isEmpty) {
      stdout.writeln("= $localeKey -- already up to date");
      continue;
    }

    final String after = encodeTranslations(translations);
    stdout.writeln("${dryRun ? "~" : "+"} $localeKey -- "
        "${changed.length} changed, ${added.length} added");
    for (final String key in [...changed, ...added]) {
      stdout.writeln("    $key");
    }

    totalChanged += changed.length;
    totalAdded += added.length;
    if (dryRun == false && after != before) {
      file.writeAsStringSync(after);
      filesWritten++;
    }
  }

  stdout.writeln("");
  if (dryRun) {
    stdout.writeln("Dry run: $totalChanged changed, $totalAdded added, "
        "nothing written.");
    return;
  }

  stdout.writeln("Wrote $filesWritten file(s): $totalChanged changed, "
      "$totalAdded added.");
  if (filesWritten > 0) {
    stdout.writeln("Now clear the edits in the app (Edit translations -> "
        "Revert this language), or the override will keep shadowing the value "
        "you just shipped.");
  }
}

/// Proves the round-trip is byte-faithful before the tool is trusted to write.
///
/// Decoding and re-encoding every shipped language file must reproduce it
/// exactly. If it does not, a promotion that changes one string would rewrite
/// the whole file and bury the real change.
bool runSelfTest() {
  final Directory directory = Directory(translationsDirectory);
  if (directory.existsSync() == false) {
    stderr.writeln("Run this from the app/ directory -- "
        "$translationsDirectory not found.");
    return false;
  }

  bool ok = true;
  for (final FileSystemEntity entity in directory.listSync()..sort(
      (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path))) {
    if (entity is! File || entity.path.endsWith(".json") == false) continue;
    final String original = entity.readAsStringSync();
    final String roundTripped = encodeTranslations(
        json.decode(original) as Map<String, dynamic>);
    if (roundTripped == original) {
      stdout.writeln("ok   ${entity.path}");
    } else {
      ok = false;
      stdout.writeln("FAIL ${entity.path} -- "
          "${original.length} bytes in, ${roundTripped.length} out");
    }
  }

  stdout.writeln(ok
      ? "\nRound-trip is byte-faithful. Safe to write."
      : "\nRound-trip changed bytes. Fix the encoder before writing.");
  return ok;
}
