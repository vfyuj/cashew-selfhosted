import 'dart:ui';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:flutter/material.dart';

class ScrollBehaviorOverride extends MaterialScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return appStateSettings["iOSEmulate"]
        ? BouncingScrollPhysics()
        : super.getScrollPhysics(context);
  }
}
