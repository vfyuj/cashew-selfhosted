import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/categoryIcon.dart';
import 'package:cashew_selfhosted/widgets/iconButtonScaled.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart'
    show RoutesToPopAfterDelete;
import 'package:cashew_selfhosted/widgets/selectCategory.dart';
import 'package:cashew_selfhosted/widgets/selectChips.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Choosing which categories a budget covers, down to individual
/// subcategories.
///
/// Tapping a main category that has subcategories takes its icon out of the row
/// and opens a line underneath for that category: "All <category>" followed by
/// each of its subcategories. Pick "All" to budget the whole category, or pick
/// specific subcategories to budget only those.
///
/// ## What ends up in `Budgets.categoryFks`
///
/// Nothing new. The column already holds a list of category pks, and the
/// spending queries already match it against **both** `transactions.categoryFk`
/// and `transactions.subCategoryFk` (the `onlyShowBasedOnCategoryFks(...) |
/// onlyShowBasedOnSubcategoryFks(...)` pair in tables.dart). So:
///
///   ["gifts"]                -> every transaction in Gifts, including ones
///                               filed under any of its subcategories
///   ["gifts-birthday", ...]  -> only transactions in those subcategories
///
/// Which is why this is a picker and not a schema change: a budget targeting
/// subcategories already worked, there was simply no way to ask for one.
///
/// Mixing is fine — all of one category plus two subcategories of another is
/// just a list with both kinds of pk in it.
class SelectCategoryWithSubCategories extends StatelessWidget {
  const SelectCategoryWithSubCategories({
    required this.selectedCategoryPks,
    required this.setSelectedCategoryPks,
    this.showSelectedAllCategoriesIfNoneSelected = false,
    super.key,
  });

  final List<String>? selectedCategoryPks;
  final void Function(List<String>?) setSelectedCategoryPks;
  final bool showSelectedAllCategoriesIfNoneSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionCategory>>(
      stream: database.watchAllCategoriesAndSubCategories(),
      builder: (context, snapshot) {
        final List<TransactionCategory> allCategories =
            snapshot.data ?? const [];
        final List<String> selected = selectedCategoryPks ?? const [];

        final Map<String, List<TransactionCategory>> subCategoriesByMainPk = {};
        for (TransactionCategory category in allCategories) {
          final String? mainPk = category.mainCategoryPk;
          if (mainPk == null) continue;
          subCategoriesByMainPk.putIfAbsent(mainPk, () => []).add(category);
        }

        // Which main categories show their subcategory line. Derived from the
        // selection rather than held as state, so it survives a rebuild and is
        // already correct when an existing budget is opened for editing: a
        // budget saved against two subcategories reopens with that line open
        // and those two chips lit.
        final List<TransactionCategory> expanded = [
          for (TransactionCategory category in allCategories)
            if (category.mainCategoryPk == null &&
                (subCategoriesByMainPk[category.categoryPk] ?? const [])
                    .isNotEmpty &&
                (selected.contains(category.categoryPk) ||
                    (subCategoriesByMainPk[category.categoryPk] ?? const [])
                        .any((TransactionCategory sub) =>
                            selected.contains(sub.categoryPk))))
              category
        ];

        // Ordered by when each category was picked, so a second one opens its
        // line below the first rather than jumping above it because it happens
        // to sort earlier. categoryFks preserves the order things were added
        // in, so the position of a category's first entry is its pick order --
        // and _SubCategoryLine edits in place, so changing one line's
        // subcategories doesn't move it.
        int pickedAt(TransactionCategory main) {
          final Set<String> pks = {
            main.categoryPk,
            for (TransactionCategory sub
                in subCategoriesByMainPk[main.categoryPk] ?? const [])
              sub.categoryPk,
          };
          final int index =
              selected.indexWhere((String pk) => pks.contains(pk));
          return index == -1 ? selected.length : index;
        }

        expanded.sort((TransactionCategory a, TransactionCategory b) =>
            pickedAt(a).compareTo(pickedAt(b)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectCategory(
              horizontalList: true,
              selectedCategories: selectedCategoryPks,
              setSelectedCategories: setSelectedCategoryPks,
              showSelectedAllCategoriesIfNoneSelected:
                  showSelectedAllCategoriesIfNoneSelected,
              // Takes the expanded categories out of the icon row -- they are
              // represented by their own line below instead. hideCategoryFks
              // only skips drawing them; they stay in the list this reports
              // back, so the subcategory picks below are never dropped by a tap
              // up here.
              hideCategoryFks: [
                for (TransactionCategory category in expanded)
                  category.categoryPk
              ],
            ),
            for (TransactionCategory mainCategory in expanded)
              _SubCategoryLine(
                mainCategory: mainCategory,
                subCategories:
                    subCategoriesByMainPk[mainCategory.categoryPk] ?? const [],
                selectedCategoryPks: selected,
                setSelectedCategoryPks: setSelectedCategoryPks,
              ),
          ],
        );
      },
    );
  }
}

/// [selection] with everything in [ownedPks] replaced by [nextPks].
///
/// Substitutes in place, where the first owned entry already sits, rather than
/// stripping and appending. The order of `categoryFks` is what orders the
/// subcategory lines on screen, so re-appending would drop a line to the
/// bottom every time somebody ticked one of its subcategories. A category with
/// nothing selected yet is new, and goes to the end — which is what puts a
/// second expanded category below the first.
///
/// Top-level and pure so the ordering rule can be tested; the widget below is
/// its only caller.
List<String> replaceCategorySelection({
  required List<String> selection,
  required Set<String> ownedPks,
  required List<String> nextPks,
}) {
  final List<String> next = [];
  bool placed = false;
  for (String pk in selection) {
    if (!ownedPks.contains(pk)) {
      next.add(pk);
      continue;
    }
    if (!placed) {
      next.addAll(nextPks);
      placed = true;
    }
  }
  if (!placed) next.addAll(nextPks);
  return next;
}

/// One expanded main category: `[x] [All <category>] [sub] [sub] ... [+]`.
class _SubCategoryLine extends StatelessWidget {
  const _SubCategoryLine({
    required this.mainCategory,
    required this.subCategories,
    required this.selectedCategoryPks,
    required this.setSelectedCategoryPks,
  });

  final TransactionCategory mainCategory;
  final List<TransactionCategory> subCategories;
  final List<String> selectedCategoryPks;
  final void Function(List<String>?) setSelectedCategoryPks;

  /// The sentinel standing in for the "All <category>" chip. Not a real pk --
  /// the main category's own pk is what gets stored for it.
  static const String _allSentinel = "__all__";

  bool get _allSelected =>
      selectedCategoryPks.contains(mainCategory.categoryPk);

  /// The category a chip stands for. The "All" chip stands for the parent.
  ///
  /// Falls back to the parent rather than throwing: the chips are built from
  /// these same lists so a miss should be impossible, but a StateError here
  /// would take down the whole budget page over a label.
  TransactionCategory _categoryFor(String pk) {
    if (pk == _allSentinel) return mainCategory;
    return subCategories.firstWhere(
      (TransactionCategory sub) => sub.categoryPk == pk,
      orElse: () => mainCategory,
    );
  }

  void _apply(List<String> next) {
    // Empty means nothing is selected anywhere, which the budget stores as
    // null ("all categories") rather than as an empty list -- the same
    // distinction setSelectedCategories already makes.
    setSelectedCategoryPks(next.isEmpty ? null : next);
  }

  /// Every pk this line owns: the main category and all of its subcategories.
  Set<String> get _myPks => {
        mainCategory.categoryPk,
        for (TransactionCategory sub in subCategories) sub.categoryPk,
      };

  List<String> _withMySelection(List<String> myNextPks) =>
      replaceCategorySelection(
        selection: selectedCategoryPks,
        ownedPks: _myPks,
        nextPks: myNextPks,
      );

  void _onSelected(String pk) {
    if (pk == _allSentinel) {
      // "All" and specific subcategories are alternatives, not additions:
      // keeping the main pk alongside a subcategory pk would match every
      // transaction in the category anyway and make the narrower pick a lie.
      _apply(_withMySelection(
          _allSelected ? const [] : [mainCategory.categoryPk]));
      return;
    }

    final List<String> currentSubs = [
      for (TransactionCategory sub in subCategories)
        if (selectedCategoryPks.contains(sub.categoryPk)) sub.categoryPk
    ];
    if (currentSubs.contains(pk)) {
      currentSubs.remove(pk);
    } else {
      currentSubs.add(pk);
    }
    _apply(_withMySelection(currentSubs));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 5, bottom: 5),
      child: SelectChips<String>(
        wrapped: false,
        allowMultipleSelected: true,
        items: [
          _allSentinel,
          for (TransactionCategory sub in subCategories) sub.categoryPk
        ],
        getSelected: (String pk) => pk == _allSentinel
            ? _allSelected
            : selectedCategoryPks.contains(pk),
        onSelected: _onSelected,
        getLabel: (String pk) => pk == _allSentinel
            ? "all".tr() + " " + mainCategory.name
            : _categoryFor(pk).name,
        // Sized from the slot SelectChips hands it rather than to a fixed
        // number, which is what every other chip row in the app does and what
        // keeps these the same size as the ones on the transaction page.
        // Passing `category` avoids looking up a row we already hold.
        getAvatar: (String pk) {
          final TransactionCategory category = _categoryFor(pk);
          return LayoutBuilder(builder: (context, constraints) {
            return CategoryIcon(
              categoryPk: "-1",
              category: category,
              emojiSize: constraints.maxWidth * 0.73,
              emojiScale: 1.2,
              size: constraints.maxWidth,
              sizePadding: 0,
              noBackground: true,
              canEditByLongPress: false,
              margin: EdgeInsetsDirectional.zero,
            );
          });
        },
        // Closes the line by dropping everything selected under this category,
        // which puts its icon back in the row above.
        extraWidgetBefore: Padding(
          padding: const EdgeInsetsDirectional.only(end: 5),
          child: IconButtonScaled(
            tooltip: "clear".tr(),
            iconData: appStateSettings["outlinedIcons"]
                ? Icons.close_outlined
                : Icons.close_rounded,
            iconSize: 18,
            scale: 1.5,
            onTap: () => _apply(_withMySelection(const [])),
          ),
        ),
        extraWidgetAfter: SelectChipsAddButtonExtraWidget(
          openPage: AddCategoryPage(
            routesToPopAfterDelete: RoutesToPopAfterDelete.One,
            mainCategoryPkWhenSubCategory: mainCategory.categoryPk,
          ),
        ),
      ),
    );
  }
}
