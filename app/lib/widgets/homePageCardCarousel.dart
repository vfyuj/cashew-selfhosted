import 'package:carousel_slider/carousel_slider.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart' show getIsFullScreen;
import 'package:cashew_selfhosted/widgets/util/widgetSize.dart';
import 'package:flutter/material.dart';

/// A row of home-page cards: swipeable on a phone, a horizontal list on a wide
/// screen.
///
/// Written once because the budgets row and the envelopes row are the same
/// thing, and the second one was a copy of the first -- the same off-screen
/// measurement, the same `getIsFullScreen` split, the same carousel options,
/// with a different card inside.
///
/// **The measurement is the part that needs explaining.** `CarouselSlider`
/// demands a fixed height, and a card's height is whatever its text wraps to.
/// So one real card is built off screen -- kept in the tree, laid out, and made
/// invisible rather than skipped, because a widget that is not laid out has no
/// height to report -- and what it measures becomes the carousel's height.
class HomePageCardCarousel extends StatefulWidget {
  const HomePageCardCarousel({
    required this.items,
    required this.measureChild,
    this.listItemPadding = EdgeInsetsDirectional.zero,
    super.key,
  });

  /// The cards, already padded however this row wants them spaced.
  final List<Widget> items;

  /// One representative card, built off screen purely to be measured. Give it
  /// the same content as a real one: a shorter stand-in measures short and
  /// clips the real cards.
  final Widget measureChild;

  /// Space around each card in the wide-screen list. The carousel branch does
  /// not use it -- there, the gap between slides comes from the viewport
  /// fraction, and extra margin would close the gap that lets the next card
  /// peek in and say there is more to swipe to.
  final EdgeInsetsDirectional listItemPadding;

  @override
  State<HomePageCardCarousel> createState() => _HomePageCardCarouselState();
}

class _HomePageCardCarouselState extends State<HomePageCardCarousel> {
  double height = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          child: Visibility(
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Opacity(
              opacity: 0,
              child: WidgetSize(
                onChange: (Size size) {
                  // Guarded: WidgetSize reports after every layout, and
                  // setting state to the value it already holds schedules
                  // another layout that reports again.
                  if (size.height == height) return;
                  setState(() => height = size.height);
                },
                child: widget.measureChild,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 13),
          child: getIsFullScreen(context)
              ? SizedBox(
                  height: height,
                  child: ListView(
                    addAutomaticKeepAlives: true,
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                    children: [
                      for (Widget item in widget.items)
                        Padding(
                          padding: widget.listItemPadding,
                          child: SizedBox(width: 500, child: item),
                        )
                    ],
                  ),
                )
              : CarouselSlider(
                  options: CarouselOptions(
                    height: height,
                    enableInfiniteScroll: false,
                    enlargeCenterPage: true,
                    enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                    viewportFraction: 0.95,
                    clipBehavior: Clip.none,
                    enlargeFactor: 0.3,
                  ),
                  items: widget.items,
                ),
        ),
      ],
    );
  }
}
