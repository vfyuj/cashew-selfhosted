import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/countNumber.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The headline figure on a budget or an envelope, and the tap that swaps
/// which of its two numbers leads.
///
/// A budget and an envelope both answer the same two questions -- how much has
/// moved, and how much is left -- and both let you tap the figure to swap which
/// one is large. The two had separate implementations of that: upstream's
/// [TotalSpent] with its two near-identical branches, and the fork's envelope
/// total beside it.
///
/// What differs between callers is only *what the two numbers are called*, so
/// that is the parameter: [contentFor] is handed the current state of the
/// setting and returns the figure to show and the words beside it.
class SwappableTotal extends StatefulWidget {
  const SwappableTotal({
    required this.contentFor,
    required this.settingKey,
    required this.pagesNeedingRefresh,
    super.key,
  });

  /// Given "is the setting on", the figure to show large and the quieter text
  /// after it.
  final SwappableTotalContent Function(bool showTotal) contentFor;

  /// The `appStateSettings` key holding which figure leads. Per-screen, and
  /// device-local: it is a display preference, not something a household has
  /// to agree on.
  final String settingKey;

  /// Which screens redraw when it is swapped, since they read the same setting.
  final List<int> pagesNeedingRefresh;

  @override
  State<SwappableTotal> createState() => _SwappableTotalState();
}

class SwappableTotalContent {
  const SwappableTotalContent({required this.amount, required this.trailing});

  /// The figure to show large.
  final double amount;

  /// The quieter text after it -- what the figure is, and what it is measured
  /// against.
  final String trailing;
}

class _SwappableTotalState extends State<SwappableTotal> {
  void _swap() {
    setState(() {});
    updateSettings(
      widget.settingKey,
      appStateSettings[widget.settingKey] != true,
      pagesNeedingRefresh: widget.pagesNeedingRefresh,
      updateGlobalState: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final SwappableTotalContent content =
        widget.contentFor(appStateSettings[widget.settingKey] == true);
    final Color textColor = Theme.of(context).colorScheme.onSecondaryContainer;

    return GestureDetector(
      onTap: _swap,
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _swap();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        // Keyed on the words rather than the number: the figure animates
        // through CountNumber, and switching on it as well would cross-fade
        // every tick of that animation.
        child: IntrinsicWidth(
          key: ValueKey(content.trailing),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CountNumber(
                count: content.amount,
                duration: const Duration(milliseconds: 400),
                initialCount: 0,
                textBuilder: (number) {
                  return TextFont(
                    text: convertToMoney(
                        Provider.of<AllWallets>(context), number,
                        finalNumber: content.amount),
                    fontSize: 22,
                    textAlign: TextAlign.start,
                    fontWeight: FontWeight.bold,
                    textColor: textColor,
                  );
                },
              ),
              Container(
                padding: const EdgeInsetsDirectional.only(bottom: 1.5),
                child: TextFont(
                  text: content.trailing,
                  fontSize: 15,
                  textAlign: TextAlign.start,
                  textColor: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
