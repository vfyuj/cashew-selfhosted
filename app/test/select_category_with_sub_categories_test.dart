import 'package:cashew_selfhosted/widgets/selectCategoryWithSubCategories.dart';
import 'package:flutter_test/flutter_test.dart';

/// A budget's `categoryFks` doubles as the order of the subcategory lines on
/// the budget page, so how the list is rewritten decides where a line appears.
/// These pin that: picking a new category opens its line at the bottom, and
/// editing an existing one leaves it where it is.
void main() {
  // "Gifts" and its three subcategories; "Personal" and its two.
  const Set<String> gifts = {'gifts', 'presents', 'charity', 'irregular'};
  const Set<String> personal = {'personal', 'taxi', 'cafe'};

  group('rewriting a category selection', () {
    test('a category with nothing selected yet goes to the end', () {
      // What makes the second expanded category open below the first rather
      // than above it.
      expect(
        replaceCategorySelection(
          selection: ['gifts'],
          ownedPks: personal,
          nextPks: ['personal'],
        ),
        ['gifts', 'personal'],
      );
    });

    test('editing a category leaves it where it already was', () {
      // Ticking a subcategory of the first category must not drop its line
      // below the second.
      expect(
        replaceCategorySelection(
          selection: ['gifts', 'personal'],
          ownedPks: gifts,
          nextPks: ['presents', 'charity'],
        ),
        ['presents', 'charity', 'personal'],
      );
    });

    test('switching from subcategories back to All keeps the position', () {
      expect(
        replaceCategorySelection(
          selection: ['presents', 'charity', 'personal'],
          ownedPks: gifts,
          nextPks: ['gifts'],
        ),
        ['gifts', 'personal'],
      );
    });

    test('clearing a category removes every trace of it', () {
      expect(
        replaceCategorySelection(
          selection: ['presents', 'charity', 'personal', 'taxi'],
          ownedPks: gifts,
          nextPks: const [],
        ),
        ['personal', 'taxi'],
      );
    });

    test('scattered entries collapse to the position of the first', () {
      // The stored list is not guaranteed tidy -- an older budget, or one
      // edited before this rule existed, can have a category's pks spread
      // through it. They gather where the first one was.
      expect(
        replaceCategorySelection(
          selection: ['presents', 'personal', 'charity'],
          ownedPks: gifts,
          nextPks: ['presents', 'charity'],
        ),
        ['presents', 'charity', 'personal'],
      );
    });

    test('everything else keeps its order and its content', () {
      expect(
        replaceCategorySelection(
          selection: ['a', 'gifts', 'b', 'c'],
          ownedPks: gifts,
          nextPks: ['charity'],
        ),
        ['a', 'charity', 'b', 'c'],
      );
    });

    test('clearing the only category leaves an empty list', () {
      // The caller turns this into null, which the budget stores as
      // "all categories".
      expect(
        replaceCategorySelection(
          selection: ['gifts'],
          ownedPks: gifts,
          nextPks: const [],
        ),
        isEmpty,
      );
    });
  });
}
