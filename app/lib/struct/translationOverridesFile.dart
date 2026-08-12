import 'dart:convert';
import 'dart:io';

import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/translationOverrides.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/util/saveFile.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Moves translation edits off the device that made them.
///
/// Overrides deliberately do not sync -- they are not user data, and pushing
/// them through the row-level feed would put UI strings in the same channel as
/// transactions. This file is how they travel instead: to another device, or
/// into the repo via `tool/merge_translation_overrides.dart`, which is what
/// makes a good translation permanent for everyone rather than local to one
/// install.

/// Identifies the file to the repo tool, which refuses anything else rather
/// than guessing at a bare `{locale: {key: value}}` map it might be handed.
const String translationOverridesFormat = "cashew-selfhosted-translation-overrides";
const int translationOverridesFormatVersion = 1;

String buildTranslationOverridesExport() {
  return const JsonEncoder.withIndent("  ").convert({
    "format": translationOverridesFormat,
    "version": translationOverridesFormatVersion,
    "appVersion": packageInfoGlobal?.version ?? "",
    "exportedAt": DateTime.now().toUtc().toIso8601String(),
    "overrides": translationOverrides,
  });
}

Future<bool> exportTranslationOverrides(BuildContext context) async {
  if (translationOverrides.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "Nothing to export",
      description: "No translations have been edited yet.",
      icon: appStateSettings["outlinedIcons"]
          ? Icons.info_outlined
          : Icons.info_rounded,
    ));
    return false;
  }

  final String stamp = DateTime.now().toIso8601String().split("T").first;
  return saveFile(
    boxContext: context,
    dataStore: null,
    dataString: buildTranslationOverridesExport(),
    fileName: "cashew-translation-overrides-$stamp.json",
    successMessage: "Translations exported",
    errorMessage: "Could not export translations",
  );
}

/// Result of an import, so the caller can report it without re-reading state.
class TranslationOverridesImportResult {
  const TranslationOverridesImportResult({
    required this.strings,
    required this.locales,
  });

  final int strings;
  final int locales;
}

/// Reads an export back in, merging rather than replacing.
///
/// Replace would be a data-loss footgun: importing a file covering only German
/// would silently drop every other language's edits. Imported values win on a
/// collision, which is what "I am bringing this file in" means.
///
/// Returns null if the user cancelled or the file was not one of ours; both
/// cases report themselves via snackbar.
Future<TranslationOverridesImportResult?> importTranslationOverrides() async {
  // No file filter -- see importDB.dart: filters throw PlatformException on
  // some platforms.
  final FilePickerResult? result = await FilePicker.platform.pickFiles();
  if (result == null) {
    openSnackbar(SnackbarMessage(
      title: "No file selected",
      icon: appStateSettings["outlinedIcons"]
          ? Icons.warning_outlined
          : Icons.warning_rounded,
    ));
    return null;
  }

  try {
    final String contents = kIsWeb
        ? utf8.decode(result.files.single.bytes!)
        : await File(result.files.single.path ?? "").readAsString();
    final Map<String, dynamic> decoded =
        json.decode(contents) as Map<String, dynamic>;

    if (decoded["format"] != translationOverridesFormat) {
      openSnackbar(SnackbarMessage(
        title: "Not a translations file",
        description: "Export one from this screen to see the format.",
        icon: appStateSettings["outlinedIcons"]
            ? Icons.warning_outlined
            : Icons.warning_rounded,
      ));
      return null;
    }

    final Map<String, dynamic> imported =
        (decoded["overrides"] as Map<String, dynamic>?) ?? {};
    int strings = 0;
    for (final MapEntry<String, dynamic> locale in imported.entries) {
      final Map<String, dynamic> values =
          locale.value as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> override in values.entries) {
        final String value = override.value.toString();
        if (value.trim().isEmpty) continue;
        translationOverrides.putIfAbsent(locale.key, () => {})[override.key] =
            value;
        strings++;
      }
    }
    await persistTranslationOverrides();

    return TranslationOverridesImportResult(
      strings: strings,
      locales: imported.keys.length,
    );
  } catch (e) {
    print("Error importing translation overrides " + e.toString());
    openSnackbar(SnackbarMessage(
      title: "Could not read that file",
      description: e.toString(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.warning_outlined
          : Icons.warning_rounded,
    ));
    return null;
  }
}
