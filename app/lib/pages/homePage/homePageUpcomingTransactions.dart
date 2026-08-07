import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/pages/upcomingOverdueTransactionsPage.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/periodCyclePicker.dart';
import 'package:cashew_selfhosted/widgets/util/keepAliveClientMixin.dart';
import 'package:cashew_selfhosted/widgets/transactionsAmountBox.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timer_builder/timer_builder.dart';

class HomePageUpcomingTransactions extends StatelessWidget {
  const HomePageUpcomingTransactions({super.key});

  @override
  Widget build(BuildContext context) {
    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Since the query uses DateTime.now()
            // We need to refresh every so often to get new data...
            // Is there a better way to do this? listen to database updates?
            TimerBuilder.periodic(Duration(seconds: 5), builder: (context) {
              return Expanded(
                child: TransactionsAmountBox(
                  openPage:
                      UpcomingOverdueTransactions(overdueTransactions: false),
                  label: "upcoming".tr(),
                  absolute: false,
                  totalWithCountStream:
                      database.watchTotalWithCountOfUpcomingOverdue(
                    allWallets: Provider.of<AllWallets>(context),
                    isOverdueTransactions: false,
                    followCustomPeriodCycle: true,
                    cycleSettingsExtension: "OverdueUpcoming",
                  ),
                  textColor: getColor(context, "unPaidUpcoming"),
                  onLongPress: () async {
                    await openOverdueUpcomingSettings(context);
                    homePageStateKey.currentState?.refreshState();
                  },
                ),
              );
            }),
            SizedBox(width: 13),
            TimerBuilder.periodic(Duration(seconds: 5), builder: (context) {
              return Expanded(
                child: TransactionsAmountBox(
                  openPage:
                      UpcomingOverdueTransactions(overdueTransactions: true),
                  label: "overdue".tr(),
                  absolute: false,
                  totalWithCountStream:
                      database.watchTotalWithCountOfUpcomingOverdue(
                    allWallets: Provider.of<AllWallets>(context),
                    isOverdueTransactions: true,
                    followCustomPeriodCycle: true,
                    cycleSettingsExtension: "OverdueUpcoming",
                  ),
                  textColor: getColor(context, "unPaidOverdue"),
                  onLongPress: () async {
                    await openOverdueUpcomingSettings(context);
                    homePageStateKey.currentState?.refreshState();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

Future openOverdueUpcomingSettings(BuildContext context) {
  return openBottomSheet(
    context,
    PopupFramework(
      title: "overdue-and-upcoming".tr(),
      subtitle: "applies-to-homepage".tr(),
      child: PeriodCyclePicker(cycleSettingsExtension: "OverdueUpcoming"),
    ),
  );
}
