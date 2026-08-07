import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/pages/accountsPage.dart';
import 'package:cashew_selfhosted/pages/autoTransactionsPageEmail.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:cashew_selfhosted/struct/iconObjects.dart';
import 'package:cashew_selfhosted/struct/keyboardIntents.dart';
import 'package:cashew_selfhosted/struct/logging.dart';
import 'package:cashew_selfhosted/widgets/fadeIn.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/initializeBiometrics.dart';
import 'package:cashew_selfhosted/widgets/util/appLinks.dart';
import 'package:cashew_selfhosted/widgets/util/onAppResume.dart';
import 'package:cashew_selfhosted/widgets/util/watchForDayChange.dart';
import 'package:cashew_selfhosted/widgets/watchAllWallets.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/struct/notificationsGlobal.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/widgets/navigationSidebar.dart';
import 'package:cashew_selfhosted/widgets/globalLoadingProgress.dart';
import 'package:cashew_selfhosted/struct/scrollBehaviorOverride.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/struct/initializeNotifications.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/restartApp.dart';
import 'package:cashew_selfhosted/struct/customDelayedCurve.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cashew_selfhosted/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_preview/device_preview.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'firebase_options.dart';
import 'package:easy_localization/easy_localization.dart';

// Requires hot restart when changed
bool enableDevicePreview = false && kDebugMode;
bool allowDebugFlags = true || kIsWeb;
bool allowDangerousDebugFlags = kDebugMode;

void main() async {
  captureLogs(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await EasyLocalization.ensureInitialized();
    sharedPreferences = await SharedPreferences.getInstance();
    // Local-only read, never blocks on network -- see specs/01-local-first-invariant.md
    await loadPersistedSelfHostedSession();
    database = await constructDb('db');
    notificationPayload = await initializeNotifications();
    entireAppLoaded = false;
    await loadCurrencyJSON();
    await loadLanguageNamesJSON();
    await initializeSettings();
    tz.initializeTimeZones();
    final String? locationName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(locationName ?? "America/New_York"));
    iconObjects.sort((a, b) => (a.mostLikelyCategoryName ?? a.icon)
        .compareTo((b.mostLikelyCategoryName ?? b.icon)));
    setHighRefreshRate();
    runApp(
      DevicePreview(
        enabled: enableDevicePreview,
        builder: (context) => InitializeLocalizations(
          child: RestartApp(
            child: InitializeApp(key: appStateKey),
          ),
        ),
      ),
    );
  });
}

GlobalKey<_InitializeAppState> appStateKey = GlobalKey();
GlobalKey<PageNavigationFrameworkState> pageNavigationFrameworkKey =
    GlobalKey();

class InitializeApp extends StatefulWidget {
  InitializeApp({Key? key}) : super(key: key);

  @override
  State<InitializeApp> createState() => _InitializeAppState();
}

class _InitializeAppState extends State<InitializeApp> {
  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return App(key: ValueKey("Main App"));
  }
}

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print("Rebuilt Material App");
    return MaterialApp(
      showPerformanceOverlay: kProfileMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale:
          enableDevicePreview ? DevicePreview.locale(context) : context.locale,
      shortcuts: shortcuts,
      actions: keyboardIntents,
      themeAnimationDuration: Duration(milliseconds: 400),
      themeAnimationCurve: CustomDelayedCurve(),
      key: ValueKey('CashewAppMain'),
      title: 'Cashew',
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      scrollBehavior: ScrollBehaviorOverride(),
      themeMode: getSettingConstants(appStateSettings)["theme"],
      home: HandleWillPopScope(
        child: Stack(
          children: [
            Row(
              children: [
                NavigationSidebar(key: sidebarStateKey),
                Expanded(
                    child: Stack(
                  children: [
                    InitialPageRouteNavigator(),
                    GlobalSnackbar(key: snackbarKey),
                  ],
                )),
              ],
            ),
            EnableSignInWithGoogleFlyIn(),
            GlobalLoadingIndeterminate(key: loadingIndeterminateKey),
            GlobalLoadingProgress(key: loadingProgressKey),
          ],
        ),
      ),
      builder: (context, child) {
        if (kReleaseMode) {
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            return Container(color: Colors.transparent);
          };
        }

        Widget mainWidget = OnAppResume(
          updateGlobalAppLifecycleState: true,
          onAppResume: () async {
            await setHighRefreshRate();
          },
          child: InitializeBiometrics(
            child: InitializeNotificationService(
              child: InitializeAppLinks(
                child: WatchForDayChange(
                  child: WatchSelectedWalletPk(
                    child: WatchAllWallets(
                      child: child ?? SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (kIsWeb) {
          return FadeIn(
              duration: Duration(milliseconds: 1000), child: mainWidget);
        } else {
          return mainWidget;
        }
      },
      // ),
    );
  }
}
