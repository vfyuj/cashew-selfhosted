import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/categoryEnvelopes.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:flutter/material.dart';

/// Builds anything that needs the envelope plan, straight from the two queries
/// it is made of.
///
/// **The category list is the outer stream, and it is the same one the
/// categories screen uses.** That is the whole point of this widget: an
/// envelope is not a row you have to own before you appear, it is a number
/// attached to a main category, so the list of envelopes is the list of
/// categories and nothing else can make it empty. A category created, deleted,
/// promoted from a subcategory or demoted back to one shows up here on the next
/// emit, because that is a write to `categories` and this is a live query on it.
///
/// The envelope amounts are the inner stream, so if that query fails or has not
/// answered yet, the rows are still drawn - just without their amounts. The
/// previous version of this had one app-wide cached snapshot fed by a manually
/// driven controller, and any hiccup in filling it (an error, a missed first
/// emit) came out as a screen with nothing on it and no explanation.
class EnvelopePlanBuilder extends StatefulWidget {
  const EnvelopePlanBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, EnvelopePlan plan) builder;

  @override
  State<EnvelopePlanBuilder> createState() => _EnvelopePlanBuilderState();
}

class _EnvelopePlanBuilderState extends State<EnvelopePlanBuilder> {
  // Held rather than created in build(), so a rebuild does not resubscribe.
  late final Stream<List<TransactionCategory>> _categories =
      database.watchAllCategories();
  late final Stream<List<CategoryEnvelope>> _envelopes =
      database.watchAllCategoryEnvelopes();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionCategory>>(
      stream: _categories,
      builder: (context, categoriesSnapshot) {
        return StreamBuilder<List<CategoryEnvelope>>(
          stream: _envelopes,
          builder: (context, envelopesSnapshot) {
            return widget.builder(
              context,
              buildEnvelopePlan(
                categoriesSnapshot.data ?? const <TransactionCategory>[],
                envelopesSnapshot.data ?? const <CategoryEnvelope>[],
              ),
            );
          },
        );
      },
    );
  }
}
