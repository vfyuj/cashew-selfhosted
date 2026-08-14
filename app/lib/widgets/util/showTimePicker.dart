import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/timeDigits.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showCustomTimePicker(
    BuildContext context, TimeOfDay initialTime,
    {String? confirmText}) async {
  minimizeKeyboard(context);
  return await openPopupCustom<TimeOfDay>(
    context,
    alignment: AlignmentDirectional.bottomCenter,
    slideFromBottom: true,
    padding: EdgeInsetsDirectional.zero,
    borderRadius: BorderRadiusDirectional.vertical(
      top: Radius.circular(getPlatform() == PlatformOS.isIOS ? 10 : 20),
    ),
    child: ScrollTimePickerPopup(
      initialTime: initialTime,
      confirmText: confirmText,
    ),
  );
}

class ScrollTimePickerPopup extends StatefulWidget {
  const ScrollTimePickerPopup({
    required this.initialTime,
    this.confirmText,
    super.key,
  });
  final TimeOfDay initialTime;
  final String? confirmText;

  @override
  State<ScrollTimePickerPopup> createState() => _ScrollTimePickerPopupState();
}

class _ScrollTimePickerPopupState extends State<ScrollTimePickerPopup> {
  late DateTime selectedDateTime = DateTime(
    2020,
    1,
    1,
    widget.initialTime.hour,
    widget.initialTime.minute,
  );

  @override
  Widget build(BuildContext context) {
    bool materialYou = appStateSettings["materialYou"] == true;
    bool use24HourFormat =
        isSetting24HourFormat() ?? isSystem24HourFormat(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: getWidthBottomSheet(context)),
      child: PopupFramework(
        title: "select-time".tr(),
        showCloseButton: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 210,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(context).brightness,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: getColor(context, "black"),
                      fontSize: 21,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: selectedDateTime,
                  use24hFormat: use24HourFormat,
                  backgroundColor: Colors.transparent,
                  onDateTimeChanged: (DateTime newDateTime) {
                    selectedDateTime = newDateTime;
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tappable(
                  onTap: () => Navigator.pop(context),
                  color: Colors.transparent,
                  borderRadius: materialYou ? 15 : 7,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 15, vertical: 10),
                    child: TextFont(
                      fontSize: materialYou ? 15 : 13,
                      textColor: Theme.of(context).colorScheme.primary,
                      text:
                          materialYou ? "cancel".tr() : "cancel".tr().allCaps,
                    ),
                  ),
                ),
                Tappable(
                  onTap: () => Navigator.pop(
                    context,
                    TimeOfDay(
                        hour: selectedDateTime.hour,
                        minute: selectedDateTime.minute),
                  ),
                  color: Colors.transparent,
                  borderRadius: materialYou ? 15 : 7,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 15, vertical: 10),
                    child: TextFont(
                      fontSize: materialYou ? 15 : 13,
                      textColor: Theme.of(context).colorScheme.primary,
                      text: materialYou
                          ? (widget.confirmText ?? "ok".tr())
                          : (widget.confirmText ?? "ok".tr()).allCaps,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
