import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/translationOverrides.dart';
import 'package:cashew_selfhosted/struct/translationOverridesFile.dart';
import 'package:cashew_selfhosted/widgets/dropdownSelect.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/noResults.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/selectChips.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/util/debouncer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;

/// Edits the app's own strings, in the app.
///
/// Everything visible on this page is a raw English literal, never `.tr()`.
/// This is the screen you reach when a translation is wrong, so it has to stay
/// readable even after someone has mangled `settings` or `cancel` -- a
/// localized escape hatch is not an escape hatch. It also means this page adds
/// no keys to en.json, so no language file has to change to ship it.
class TranslationEditorPage extends StatefulWidget {
  const TranslationEditorPage({super.key});

  @override
  State<TranslationEditorPage> createState() => _TranslationEditorPageState();
}

/// Which subset of the strings is on screen.
enum _TranslationFilter { all, missing, overridden }

/// One translatable string, as the editor sees it.
class _TranslationRow {
  _TranslationRow({
    required this.key,
    required this.english,
    required this.bundled,
    required this.override,
  });

  final String key;

  /// The shipped English string. Deliberately the *bundled* value even when
  /// English itself has been overridden -- it is the reference for what the key
  /// means, and it must not move under whoever is translating.
  final String english;

  /// What this language ships for the key. Null means the key is absent from
  /// this language's file, so the app falls back to English.
  final String? bundled;

  /// What the user has set it to, if anything.
  final String? override;

  /// Lowercased `key + english + current translation`, computed once so search
  /// is a scan over 1300 precomputed strings rather than 1300 rebuilds.
  late final String haystack =
      (key + " " + english + " " + effective).toLowerCase();

  String get effective => override ?? bundled ?? english;
  bool get isMissing => bundled == null;
  bool get isOverridden => override != null;

  /// A translation that dropped or invented a `{placeholder}`. Inventing one is
  /// always a bug: it renders literally.
  bool get hasPlaceholderMismatch =>
      _placeholders(english).difference(_placeholders(effective)).isNotEmpty ||
      _placeholders(effective).difference(_placeholders(english)).isNotEmpty;
}

final RegExp _placeholderMatcher = RegExp(r'\{\w+\}');

Set<String> _placeholders(String value) =>
    _placeholderMatcher.allMatches(value).map((m) => m.group(0)!).toSet();

class _TranslationEditorPageState extends State<TranslationEditorPage> {
  /// Which language is being edited. Defaults to the one actually on screen,
  /// not appStateSettings["locale"] -- that reads "System" for most users.
  late String targetLocaleKey = supportedLocales.containsKey(
          context.locale.languageCode)
      ? context.locale.languageCode
      : "en";

  String searchValue = "";
  _TranslationFilter filter = _TranslationFilter.all;
  final Debouncer searchDebouncer = Debouncer(milliseconds: 200);

  List<_TranslationRow>? rows;

  @override
  void initState() {
    super.initState();
    loadRows();
  }

  bool get isEditingEnglish => targetLocaleKey == "en";

  Future<void> loadRows() async {
    final Map<String, dynamic> english =
        await bundledTranslations(supportedLocales["en"]!);
    final Map<String, dynamic> target = isEditingEnglish
        ? english
        : await bundledTranslations(supportedLocales[targetLocaleKey]!);
    final Map<String, String> overrides =
        translationOverrides[targetLocaleKey] ?? {};

    // en.json is the key list by definition: translation_keys_test.dart fails
    // the build if a .tr() key is missing from it, and a key in another
    // language that English does not have is unreachable.
    final List<_TranslationRow> built = [
      for (final MapEntry<String, dynamic> entry in english.entries)
        _TranslationRow(
          key: entry.key,
          english: entry.value.toString(),
          bundled: target[entry.key]?.toString(),
          override: overrides[entry.key],
        ),
    ];

    if (mounted) setState(() => rows = built);
  }

  List<_TranslationRow> get visibleRows {
    if (rows == null) return const [];
    final String needle = searchValue.trim().toLowerCase();
    return [
      for (final _TranslationRow row in rows!)
        if (_matchesFilter(row) &&
            (needle.isEmpty || row.haystack.contains(needle)))
          row,
    ];
  }

  bool _matchesFilter(_TranslationRow row) {
    switch (filter) {
      case _TranslationFilter.all:
        return true;
      case _TranslationFilter.missing:
        return row.isMissing;
      case _TranslationFilter.overridden:
        return row.isOverridden;
    }
  }

  Future<void> saveOverride(_TranslationRow row, String? value) async {
    // An unchanged value is stored as nothing, so "Overridden" keeps meaning
    // "differs from what shipped" rather than "was opened once".
    final String? normalized =
        (value?.trim().isEmpty ?? true) || value == row.bundled ? null : value;
    await setTranslationOverride(targetLocaleKey, row.key, normalized);
    await applyTranslationOverridesNow(context);
    await loadRows();
  }

  void confirmRevert({required String title, required Future<void> Function() onRevert}) {
    openPopup(
      context,
      title: title,
      description: "The strings that ship with the app will be used again. "
          "Your other settings and data are untouched.",
      icon: appStateSettings["outlinedIcons"]
          ? Icons.undo_outlined
          : Icons.undo_rounded,
      onCancel: () => popRoute(context),
      onCancelLabel: "Cancel",
      onSubmit: () async {
        popRoute(context);
        await onRevert();
        await applyTranslationOverridesNow(context);
        await loadRows();
        openSnackbar(SnackbarMessage(
          title: "Reverted",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.undo_outlined
              : Icons.undo_rounded,
        ));
      },
      onSubmitLabel: "Revert",
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_TranslationRow> visible = visibleRows;
    final int overriddenCount =
        rows?.where((_TranslationRow r) => r.isOverridden).length ?? 0;

    return WillPopScope(
      onWillPop: () async {
        if (searchValue != "") {
          setState(() => searchValue = "");
          return false;
        }
        return true;
      },
      child: PageFramework(
        horizontalPaddingConstrained: true,
        dragDownToDismiss: true,
        title: "Edit translations",
        scrollToTopButton: true,
        actions: [
          CustomPopupMenuButton(
            showButtons: true,
            keepOutFirst: true,
            items: [
              DropdownItemMenu(
                id: "export",
                label: "Export edits",
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.upload_file_outlined
                    : Icons.upload_file_rounded,
                action: () => exportTranslationOverrides(context),
              ),
              DropdownItemMenu(
                id: "import",
                label: "Import edits",
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.file_download_outlined
                    : Icons.file_download_rounded,
                action: () async {
                  final TranslationOverridesImportResult? result =
                      await importTranslationOverrides();
                  if (result == null || !mounted) return;
                  await applyTranslationOverridesNow(context);
                  await loadRows();
                  openSnackbar(SnackbarMessage(
                    title: "Translations imported",
                    description: "${result.strings} strings across "
                        "${result.locales} languages",
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.file_download_outlined
                        : Icons.file_download_rounded,
                  ));
                },
              ),
              DropdownItemMenu(
                id: "revert-language",
                label: "Revert this language",
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.undo_outlined
                    : Icons.undo_rounded,
                action: () => confirmRevert(
                  title: "Revert ${languageDisplayFilter(targetLocaleKey)}?",
                  onRevert: () =>
                      clearTranslationOverridesForLocale(targetLocaleKey),
                ),
              ),
              DropdownItemMenu(
                id: "revert-all",
                label: "Revert every language",
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.delete_outlined
                    : Icons.delete_rounded,
                action: () => confirmRevert(
                  title: "Revert every language?",
                  onRevert: clearAllTranslationOverrides,
                ),
              ),
            ],
          ),
        ],
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LanguagePicker(
                  selected: targetLocaleKey,
                  onSelected: (String localeKey) {
                    setState(() {
                      targetLocaleKey = localeKey;
                      rows = null;
                      if (localeKey == "en" &&
                          filter == _TranslationFilter.missing) {
                        filter = _TranslationFilter.all;
                      }
                    });
                    loadRows();
                  },
                ),
                if (isEditingEnglish)
                  const _EditorNote(
                    "Editing English also changes what every other language "
                    "falls back to, including the strings none of them "
                    "translate yet.",
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  child: TextInput(
                    labelText: "Search text or key",
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.search_outlined
                        : Icons.search_rounded,
                    onChanged: (String value) => searchDebouncer.run(() {
                      if (mounted) setState(() => searchValue = value);
                    }),
                    onSubmitted: (String value) {
                      if (mounted) setState(() => searchValue = value);
                    },
                  ),
                ),
                SelectChips<_TranslationFilter>(
                  allowMultipleSelected: false,
                  wrapped: true,
                  items: [
                    _TranslationFilter.all,
                    if (isEditingEnglish == false) _TranslationFilter.missing,
                    _TranslationFilter.overridden,
                  ],
                  getSelected: (_TranslationFilter item) => filter == item,
                  onSelected: (_TranslationFilter item) =>
                      setState(() => filter = item),
                  getLabel: (_TranslationFilter item) {
                    switch (item) {
                      case _TranslationFilter.all:
                        return "All (${rows?.length ?? 0})";
                      case _TranslationFilter.missing:
                        return "Not translated "
                            "(${rows?.where((r) => r.isMissing).length ?? 0})";
                      case _TranslationFilter.overridden:
                        return "Edited ($overriddenCount)";
                    }
                  },
                ),
                const SizedBox(height: 5),
              ],
            ),
          ),
          if (rows == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (visible.isEmpty)
            SliverToBoxAdapter(
              child: NoResults(
                message: searchValue.trim().isEmpty
                    ? "Nothing here yet."
                    : "No strings match that search.",
                noSearchResultsVariation: true,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => _TranslationRowEntry(
                  row: visible[index],
                  showEnglish: isEditingEnglish == false,
                  onTap: () => openRowEditor(visible[index]),
                ),
                childCount: visible.length,
              ),
            ),
        ],
      ),
    );
  }

  void openRowEditor(_TranslationRow row) {
    openBottomSheet(
      context,
      popupWithKeyboard: true,
      PopupFramework(
        title: row.key,
        subtitle: languageDisplayFilter(targetLocaleKey),
        child: _TranslationRowEditor(
          row: row,
          showEnglish: isEditingEnglish == false,
          onSave: (String value) async {
            popRoute(context);
            await saveOverride(row, value);
          },
          onRevert: row.isOverridden
              ? () async {
                  popRoute(context);
                  await saveOverride(row, null);
                }
              : null,
        ),
      ),
    );
  }
}

/// The eight languages, as chips. Reuses [languageDisplayFilter] so the names
/// read the way they do in the language picker.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.selected, required this.onSelected});

  final String selected;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: SelectChips<String>(
        allowMultipleSelected: false,
        items: supportedLocales.keys.toList(),
        getSelected: (String item) => item == selected,
        onSelected: onSelected,
        getLabel: languageDisplayFilter,
      ),
    );
  }
}

class _EditorNote extends StatelessWidget {
  const _EditorNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
          borderRadius: BorderRadius.circular(15),
        ),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 12),
        child: TextFont(
          text: text,
          fontSize: 14,
          maxLines: 5,
          textColor: getColor(context, "black"),
        ),
      ),
    );
  }
}

/// One row: the key, the English source, and what this language currently says.
class _TranslationRowEntry extends StatelessWidget {
  const _TranslationRowEntry({
    required this.row,
    required this.showEnglish,
    required this.onTap,
  });

  final _TranslationRow row;
  final bool showEnglish;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      color: Colors.transparent,
      child: Padding(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: row.key,
                    fontSize: 12,
                    maxLines: 1,
                    textColor: getColor(context, "textLight"),
                  ),
                ),
                if (row.hasPlaceholderMismatch)
                  const _RowBadge("placeholder", isWarning: true),
                if (row.isMissing) const _RowBadge("not translated"),
                if (row.isOverridden) const _RowBadge("edited"),
              ],
            ),
            const SizedBox(height: 3),
            TextFont(
              text: row.effective,
              fontSize: 16,
              maxLines: 4,
              textColor: row.isMissing
                  ? getColor(context, "textLight")
                  : getColor(context, "black"),
            ),
            if (showEnglish) ...[
              const SizedBox(height: 2),
              TextFont(
                text: row.english,
                fontSize: 13,
                maxLines: 3,
                textColor: getColor(context, "textLight"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowBadge extends StatelessWidget {
  const _RowBadge(this.label, {this.isWarning = false});

  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final Color color = isWarning
        ? getColor(context, "unPaidOverdue")
        : Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 7, vertical: 2),
        child: TextFont(text: label, fontSize: 11, textColor: color),
      ),
    );
  }
}

/// The edit sheet for a single string.
class _TranslationRowEditor extends StatefulWidget {
  const _TranslationRowEditor({
    required this.row,
    required this.showEnglish,
    required this.onSave,
    required this.onRevert,
  });

  final _TranslationRow row;
  final bool showEnglish;
  final Future<void> Function(String) onSave;
  final Future<void> Function()? onRevert;

  @override
  State<_TranslationRowEditor> createState() => _TranslationRowEditorState();
}

class _TranslationRowEditorState extends State<_TranslationRowEditor> {
  late final TextEditingController controller =
      TextEditingController(text: widget.row.effective);
  late String value = widget.row.effective;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Placeholders the English has that this translation dropped, and any it
  /// invented. Dropping one can be a deliberate choice; inventing one always
  /// renders the braces literally.
  String? get placeholderWarning {
    final Set<String> source = _placeholders(widget.row.english);
    final Set<String> entered = _placeholders(value);
    final Set<String> dropped = source.difference(entered);
    final Set<String> invented = entered.difference(source);
    if (invented.isNotEmpty) {
      return "${invented.join(", ")} is not in the English text and will be "
          "shown exactly as written, braces and all.";
    }
    if (dropped.isNotEmpty) {
      return "${dropped.join(", ")} is missing. It gets replaced with a real "
          "value at runtime, so leaving it out drops that value.";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? warning = placeholderWarning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showEnglish) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(
                bottom: 12, start: 5, end: 5),
            child: TextFont(
              text: widget.row.english,
              fontSize: 15,
              maxLines: 6,
              textColor: getColor(context, "textLight"),
            ),
          ),
        ],
        TextInput(
          labelText: "Translation",
          controller: controller,
          autoFocus: true,
          minLines: 1,
          maxLines: 6,
          padding: EdgeInsetsDirectional.zero,
          onChanged: (String entered) => setState(() => value = entered),
        ),
        if (warning != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 10, start: 5, end: 5),
            child: TextFont(
              text: warning,
              fontSize: 13,
              maxLines: 4,
              textColor: getColor(context, "unPaidOverdue"),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8),
          child: TextFont(
            text: "Clearing the box restores the string the app ships with.",
            fontSize: 12,
            maxLines: 2,
            textColor: getColor(context, "textLight"),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (widget.onRevert != null) ...[
              Expanded(
                child: _SheetButton(
                  label: "Revert",
                  filled: false,
                  onTap: () => widget.onRevert!(),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _SheetButton(
                label: "Save",
                filled: true,
                onTap: () => widget.onSave(value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = filled
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4);
    return Tappable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      color: background,
      borderRadius: 15,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
        child: Center(
          child: TextFont(
            text: label,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            textColor: getColor(context, "black"),
          ),
        ),
      ),
    );
  }
}
