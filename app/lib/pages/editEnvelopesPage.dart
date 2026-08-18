import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/addCategoryPage.dart';
import 'package:cashew_selfhosted/pages/editBudgetPage.dart'
    show TotalSpentToggle;
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/categoryIcon.dart';
import 'package:cashew_selfhosted/widgets/dropdownSelect.dart';
import 'package:cashew_selfhosted/widgets/editRowEntry.dart';
import 'package:cashew_selfhosted/widgets/envelopePlanBuilder.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart'
    show RoutesToPopAfterDelete;
import 'package:cashew_selfhosted/widgets/sliverStickyLabelDivider.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide SliverReorderableList;
import 'package:flutter/services.dart';
import 'package:cashew_selfhosted/modified/reorderable_list.dart';
import 'package:provider/provider.dart';
import 'package:sliver_tools/sliver_tools.dart';

// Edit Envelopes: the order they are drawn in, and how much of an envelope the
// screen leads with.
//
// Deliberately smaller than Edit Budgets, because there is less here to edit. An
// envelope cannot be added or deleted -- it exists because a main category
// exists (docs/app/envelopes.md) -- so this page has no add button and no swipe
// to delete. Tapping a row opens the category, which is where a name, colour or
// icon actually lives.
//
// **The order is `Categories.order`, the household's own column**, which is what
// the envelopes list has always been drawn in. So a drag here rides the ordinary
// change feed like any other edit, everyone sharing the data sees the same
// order, and the screen redraws itself because the order is a query rather than
// a setting -- there is nothing to store, refresh or reconcile.
//
// The visible consequence, and it is deliberate: this is the *same* order the
// categories screen has. Reordering envelopes reorders categories.
class EditEnvelopesPage extends StatefulWidget {
  const EditEnvelopesPage({super.key});

  @override
  State<EditEnvelopesPage> createState() => _EditEnvelopesPageState();
}

class _EditEnvelopesPageState extends State<EditEnvelopesPage> {
  bool dragDownToDismissEnabled = true;
  int currentReorder = -1;

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      dragDownToDismissEnabled: dragDownToDismissEnabled,
      title: "edit-envelopes".tr(),
      scrollToTopButton: true,
      actions: [
        CustomPopupMenuButton(
          showButtons: true,
          keepOutFirst: true,
          items: [
            DropdownItemMenu(
              id: "settings",
              label: "settings".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.more_vert_outlined
                  : Icons.more_vert_rounded,
              action: () => openBottomSheet(
                context,
                PopupFramework(hasPadding: false, child: EnvelopeSettings()),
              ),
            ),
          ],
        ),
      ],
      slivers: [
        EnvelopePlanBuilder(
          builder: (context, plan) {
            return MultiSliver(
              children: [
                _ReorderableSection(
                  plan: plan,
                  income: false,
                  currentReorder: currentReorder,
                  onReorderStart: _onReorderStart,
                  onReorderEnd: _onReorderEnd,
                ),
                _ReorderableSection(
                  plan: plan,
                  income: true,
                  currentReorder: currentReorder,
                  onReorderStart: _onReorderStart,
                  onReorderEnd: _onReorderEnd,
                ),
              ],
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }

  void _onReorderStart(int index) {
    HapticFeedback.heavyImpact();
    setState(() {
      dragDownToDismissEnabled = false;
      currentReorder = index;
    });
  }

  void _onReorderEnd(int _) {
    setState(() {
      dragDownToDismissEnabled = true;
      currentReorder = -1;
    });
  }
}

/// The settings sheet behind the corner button.
///
/// Upstream's own toggle, pointed at the envelope setting rather than the budget
/// one, so the radio sheet, the labels and both worked examples come from the
/// same place the budgets screen gets them.
class EnvelopeSettings extends StatelessWidget {
  const EnvelopeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return TotalSpentToggle(
      settingKey: "showTotalSpentForEnvelope",
      titleLabel: "envelope-total-type".tr(),
      // The home page carousel and the envelopes page both draw the figure this
      // changes, and neither is watching a query.
      pagesNeedingRefresh: [0, 4],
    );
  }
}

/// One side of the ledger, reorderable on its own.
///
/// Two lists rather than one, because the envelopes page draws income and
/// expense as two sections: a drag that moved a category across the divide would
/// look like it had done nothing. Each section rearranges only the order slots
/// its own categories already occupy, so the other half stays put.
class _ReorderableSection extends StatelessWidget {
  const _ReorderableSection({
    required this.plan,
    required this.income,
    required this.currentReorder,
    required this.onReorderStart,
    required this.onReorderEnd,
  });

  final EnvelopePlan plan;
  final bool income;
  final int currentReorder;
  final void Function(int index) onReorderStart;
  final void Function(int index) onReorderEnd;

  @override
  Widget build(BuildContext context) {
    final List<TransactionCategory> categories =
        plan.categoriesOfType(income: income);
    if (categories.isEmpty) return SliverToBoxAdapter();
    final DateTime month = envelopePeriodStart(DateTime.now());

    // A plain label rather than SliverStickyLabelDivider: nothing else in the
    // app pins a sticky header over a reorderable sliver, and a sticky header
    // shifts the paint origin of the sliver underneath it -- which is exactly
    // what the drag proxy measures itself against. Not worth finding out here.
    return MultiSliver(
      children: [
        SliverToBoxAdapter(
          child:
              StickyLabelDivider(info: income ? "income".tr() : "expense".tr()),
        ),
        SliverReorderableList(
          onReorderStart: onReorderStart,
          onReorderEnd: onReorderEnd,
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final TransactionCategory category = categories[index];
            final double? amount = plan.amountFor(category.categoryPk, month);
            return Stack(
              key: ValueKey(index),
              children: [
                EditRowEntry(
                  key: ValueKey(category.categoryPk),
                  index: index,
                  // An envelope has nothing of its own to delete -- deleting the
                  // category is what removes it, and that belongs on the category
                  // screen where the consequences are spelled out.
                  canDelete: false,
                  canReorder: categories.length != 1,
                  currentReorder:
                      currentReorder != -1 && currentReorder != index,
                  accentColor: dynamicPastel(
                    context,
                    HexColor(category.colour,
                        defaultColor: Theme.of(context).colorScheme.primary),
                    amountLight: 0.55,
                    amountDark: 0.35,
                  ),
                  openPage: AddCategoryPage(
                    category: category,
                    routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                  ),
                  content: Row(
                    children: [
                      CategoryIcon(
                        category: category,
                        categoryPk: category.categoryPk,
                        size: 26,
                        sizePadding: 14,
                        margin: EdgeInsetsDirectional.zero,
                        canEditByLongPress: false,
                      ),
                      SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFont(
                              text: category.name,
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                              maxLines: 1,
                            ),
                            TextFont(
                              // This month's plan, so the rows can be put in an
                              // order that means something rather than sorted by
                              // name from memory.
                              text: convertToMoney(
                                      Provider.of<AllWallets>(context),
                                      amount ?? 0) +
                                  " " +
                                  "planned".tr().toLowerCase(),
                              fontSize: 15,
                              textColor: getColor(context, "textLight"),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          onReorder: (int oldIndex, int newIndex) async {
            // SliverReorderableList reports the destination as an insertion
            // point in the pre-removal list, so a downward move is one too far
            // once the dragged row is taken out.
            if (newIndex > oldIndex) newIndex -= 1;
            final List<TransactionCategory> reordered = [...categories];
            reordered.insert(newIndex, reordered.removeAt(oldIndex));
            // No setState and nothing to refresh: this writes to the categories
            // table, and the list is drawn from a live query on it.
            await database.reorderCategoriesWithinTheirSlots([
              for (TransactionCategory category in reordered)
                category.categoryPk
            ]);
            return true;
          },
        ),
      ],
    );
  }
}
