import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:cashew_selfhosted/pages/addTransactionPage.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/animatedExpanded.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/dropdownSelect.dart';
import 'package:cashew_selfhosted/widgets/fadeIn.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/iconButtonScaled.dart';
import 'package:cashew_selfhosted/widgets/moreIcons.dart';
import 'package:cashew_selfhosted/widgets/navigationFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:cashew_selfhosted/widgets/extraInfoBoxes.dart';
import 'package:cashew_selfhosted/widgets/outlinedButtonStacked.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({Key? key}) : super(key: key);

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  bool currentlyExporting = false;
  bool signingIn = false;
  String? signInError;
  // On web the app is always served from the same origin as its own API
  // (see DEPLOYMENT.md -- one container serves both), so there's exactly
  // one correct server URL and asking the user to type it in is just a
  // chance to get it wrong. Native builds are a single generic binary that
  // could point at anyone's server, so those still need the manual field
  // (same as e.g. a Nextcloud mobile app).
  final TextEditingController serverUrlController = TextEditingController(
      text: kIsWeb ? Uri.base.origin : appStateSettings["serverUrl"]);
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  void refreshState() {
    setState(() {});
  }

  Future<void> submitSignIn() async {
    setState(() {
      signingIn = true;
      signInError = null;
    });
    final success = await selfHostedLogin(
      serverUrl: serverUrlController.text,
      email: emailController.text,
      password: passwordController.text,
    );
    if (success) {
      await syncAfterLogin(context);
      refreshUIAfterLoginChange();
    }
    if (mounted) {
      setState(() {
        signingIn = false;
        signInError = success ? null : "invalid-login".tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget profileWidget = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dynamicPastel(context, Theme.of(context).colorScheme.primary,
            amount: 0.2),
      ),
      child: Center(
        child: TextFont(
            text: (selfHostedSession?.email.isNotEmpty == true
                ? selfHostedSession!.email[0].toUpperCase()
                : ""),
            fontSize: 60,
            textAlign: TextAlign.center,
            fontWeight: FontWeight.bold,
            textColor: dynamicPastel(
                context, Theme.of(context).colorScheme.primary,
                amount: 0.85, inverse: false)),
      ),
    );
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: getPlatform() == PlatformOS.isIOS
          ? "backup".tr()
          : "data-backup".tr(),
      appBarBackgroundColor: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      appBarBackgroundColorStart: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      bottomPadding: false,
      actions: [],
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: selfHostedSession == null
                ? Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 18.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextFont(
                          text: "self-hosted-backup".tr(),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        if (!kIsWeb) ...[
                          TextInput(
                            labelText: "server-url".tr(),
                            controller: serverUrlController,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            padding: EdgeInsetsDirectional.zero,
                          ),
                          SizedBox(height: 10),
                        ],
                        TextInput(
                          labelText: "email".tr(),
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          padding: EdgeInsetsDirectional.zero,
                        ),
                        SizedBox(height: 10),
                        TextInput(
                          labelText: "password".tr(),
                          controller: passwordController,
                          obscureText: true,
                          autocorrect: false,
                          padding: EdgeInsetsDirectional.zero,
                          onSubmitted: (_) => submitSignIn(),
                        ),
                        if (signInError != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(top: 10),
                            child: TextFont(
                              text: signInError!,
                              textColor: Theme.of(context).colorScheme.error,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(height: 20),
                        Button(
                          label: "sign-in-to-server".tr(),
                          disabled: signingIn,
                          onTap: submitSignIn,
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 35),
                      ClipOval(child: profileWidget),
                      SizedBox(height: 10),
                      TextFont(
                        text: "self-hosted-backup".tr(),
                        textAlign: TextAlign.center,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                      SizedBox(height: 2),
                      TextFont(
                        text: (appStateSettings["currentUserEmail"] ?? "")
                            .toString(),
                        textAlign: TextAlign.center,
                        fontSize: 15,
                      ),
                      SizedBox(height: 15),
                      IntrinsicWidth(
                        child: Button(
                          label: "logout".tr(),
                          onTap: () async {
                            final result = await selfHostedLogout();
                            if (result == true) {
                              if (getIsFullScreen(context) == false) {
                                maybePopRoute(context);
                                settingsPageStateKey.currentState
                                    ?.refreshState();
                              } else {
                                pageNavigationFrameworkKey.currentState!
                                    .changePage(0, switchNavbar: true);
                              }
                            }
                            refreshUIAfterLoginChange();
                          },
                          padding: EdgeInsetsDirectional.symmetric(
                              horizontal: 17, vertical: 12),
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 25),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 18.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: IgnorePointer(
                                ignoring: currentlyExporting,
                                child: AnimatedOpacity(
                                  opacity: currentlyExporting ? 0.4 : 1,
                                  duration: Duration(milliseconds: 200),
                                  child: OutlinedButtonStacked(
                                    text: "backup".tr(),
                                    iconData: appStateSettings["outlinedIcons"]
                                        ? Icons.cloud_upload_outlined
                                        : Icons.cloud_upload_rounded,
                                    customIconBuilder: (icon) => BouncingWidget(
                                      animate: currentlyExporting,
                                      child: icon,
                                    ),
                                    onTap: () async {
                                      setState(() {
                                        currentlyExporting = true;
                                      });
                                      await createBackup(context,
                                          deleteOldBackups: true);
                                      if (mounted)
                                        setState(() {
                                          currentlyExporting = false;
                                        });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 15),
                            Expanded(
                              child: OutlinedButtonStacked(
                                text: "restore".tr(),
                                iconData: appStateSettings["outlinedIcons"]
                                    ? Icons.cloud_download_outlined
                                    : Icons.cloud_download_rounded,
                                onTap: () async {
                                  await chooseBackup(context);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 15),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 18.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: SyncCloudBackupButton(
                                onTap: () async {
                                  chooseBackup(context,
                                      isManaging: true, isClientSync: true);
                                },
                              ),
                            ),
                            SizedBox(width: 18),
                            Expanded(
                              child: BackupsCloudBackupButton(
                                onTap: () async {
                                  await chooseBackup(context, isManaging: true);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 15),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 18.0),
                        child: BackupDestinationSettings(),
                      ),
                      // if (kIsWeb)
                      //   Padding(
                      //     padding: const EdgeInsetsDirectional.symmetric(
                      //         horizontal: 18, vertical: 15),
                      //     child: SettingsContainerSwitch(
                      //       icon: appStateSettings["outlinedIcons"]
                      //           ? Icons.key_outlined
                      //           : Icons.key_rounded,
                      //       isOutlined: true,
                      //       horizontalPadding: 20,
                      //       title: "automatic-google-login-popup-web".tr(),
                      //       description:
                      //           "automatic-google-login-popup-web-description"
                      //               .tr(),
                      //       initialValue: appStateSettings[
                      //               "webForceLoginPopupOnLaunch"] ==
                      //           true,
                      //       onSwitched: (value) async {
                      //         await updateSettings(
                      //             "webForceLoginPopupOnLaunch", value,
                      //             updateGlobalState: false);
                      //       },
                      //     ),
                      //   ),
                      SizedBox(height: 75),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class SyncCloudBackupButton extends StatelessWidget {
  const SyncCloudBackupButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonStacked(
      text: getPlatform() == PlatformOS.isIOS
          ? "devices".tr().capitalizeFirst
          : "sync".tr(),
      iconData: getPlatform() == PlatformOS.isIOS
          ? appStateSettings["outlinedIcons"]
              ? Icons.devices_outlined
              : Icons.devices_rounded
          : appStateSettings["outlinedIcons"]
              ? Icons.cloud_sync_outlined
              : Icons.cloud_sync_rounded,
      onTap: onTap,
    );
  }
}

class BackupsCloudBackupButton extends StatelessWidget {
  const BackupsCloudBackupButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonStacked(
      text: "backups".tr(),
      iconData: appStateSettings["outlinedIcons"]
          ? Icons.folder_outlined
          : Icons.folder_rounded,
      onTap: onTap,
    );
  }
}

class EnableSignInWithGoogleFlyIn extends StatelessWidget {
  const EnableSignInWithGoogleFlyIn({super.key});

  @override
  Widget build(BuildContext context) {
    if (appStateSettings["enableGoogleLoginFlyIn"] != true ||
        getIsFullScreen(context) == false) return SizedBox.shrink();
    return const SignInWithGoogleFlyIn();
  }
}

class SignInWithGoogleFlyIn extends StatefulWidget {
  const SignInWithGoogleFlyIn({super.key});

  @override
  State<SignInWithGoogleFlyIn> createState() => _SignInWithGoogleFlyInState();
}

class _SignInWithGoogleFlyInState extends State<SignInWithGoogleFlyIn> {
  bool hide = true;

  @override
  void initState() {
    checkCloudFunctionsStatus();
    super.initState();
  }

  void checkCloudFunctionsStatus() {
    Future.delayed(Duration(seconds: 1), () {
      if (!runningCloudFunctions && entireAppLoaded) {
        setState(() {
          hide = false;
        });
      } else {
        checkCloudFunctionsStatus();
      }
    });
  }

  bool get shouldExpand => !hide && googleUser == null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
      child: SlideFadeTransition(
        animate: true,
        animationDuration: Duration(milliseconds: 1700),
        curve: ElasticOutCurve(0.8),
        delayStart: Duration(milliseconds: 1900),
        offset: -0.5,
        child: AnimatedExpanded(
          expand: shouldExpand,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadiusDirectional.all(Radius.circular(13)),
                      color: getColor(context, "lightDarkAccentHeavyLight"),
                      boxShadow: boxShadowCheck(boxShadowSharp(context)),
                    ),
                    child: Tappable(
                      onTap: () async {
                        await signInGoogle();
                        setState(() {
                          hide = true;
                        });
                      },
                      borderRadius: 13,
                      color: dynamicPastel(
                        context,
                        Theme.of(context).colorScheme.secondaryContainer,
                        amount: 0.6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 25,
                                end: 15,
                                top: 15,
                                bottom: 15,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        MoreIcons.google,
                                        size: 25,
                                      ),
                                      SizedBox(width: 10),
                                      TextFont(
                                        text: "sign-in-with-google".tr(),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 18.0),
                                    child: IconButtonScaled(
                                      iconData:
                                          appStateSettings["outlinedIcons"]
                                              ? Icons.close_outlined
                                              : Icons.close_rounded,
                                      iconSize: 18,
                                      scale: 1.5,
                                      onTap: () async {
                                        setState(() {
                                          hide = true;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          HorizontalBreak(
                            padding: EdgeInsetsDirectional.zero,
                            color: dynamicPastel(
                              context,
                              Theme.of(context).colorScheme.secondaryContainer,
                              amount: 0.1,
                              inverse: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 22, vertical: 12),
                            child: Button(
                              label: "Continue with Google",
                              onTap: () async {
                                await signInGoogle();
                                setState(() {
                                  hide = true;
                                });
                              },
                              color: Theme.of(context).colorScheme.primary,
                              textColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              borderRadius: 5,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 22, end: 22, bottom: 22),
                            child: TextFont(
                              text: "onboarding-info-3".tr(),
                              maxLines: 10,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick where *backups* (not sync) are stored: this fork's
/// own server (default) or an arbitrary WebDAV endpoint such as Nextcloud.
/// See specs/03-stage-1-kill-google.md -- WebDAV credentials are stored
/// only in local app settings; the self-hosted server never sees them.
class BackupDestinationSettings extends StatefulWidget {
  const BackupDestinationSettings({super.key});

  @override
  State<BackupDestinationSettings> createState() =>
      _BackupDestinationSettingsState();
}

class _BackupDestinationSettingsState
    extends State<BackupDestinationSettings> {
  late String backupTarget = appStateSettings["backupTarget"];
  final TextEditingController webdavUrlController =
      TextEditingController(text: appStateSettings["webdavUrl"]);
  final TextEditingController webdavUsernameController =
      TextEditingController(text: appStateSettings["webdavUsername"]);
  final TextEditingController webdavPasswordController =
      TextEditingController(text: appStateSettings["webdavPassword"]);
  final TextEditingController webdavFolderController =
      TextEditingController(text: appStateSettings["webdavFolder"]);

  Future<void> saveWebdavSettings() async {
    await updateSettings("webdavUrl", webdavUrlController.text.trim(),
        updateGlobalState: false);
    await updateSettings(
        "webdavUsername", webdavUsernameController.text.trim(),
        updateGlobalState: false);
    await updateSettings("webdavPassword", webdavPasswordController.text,
        updateGlobalState: false);
    await updateSettings(
        "webdavFolder",
        webdavFolderController.text.trim().isEmpty
            ? "cashew-backups"
            : webdavFolderController.text.trim(),
        updateGlobalState: false);
    openSnackbar(SnackbarMessage(title: "webdav-settings-saved".tr()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsContainerDropdown(
          enableBorderRadius: true,
          title: "backup-destination".tr(),
          description: "backup-destination-description".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.cloud_outlined
              : Icons.cloud_rounded,
          initial: backupTarget,
          items: ["server", "webdav"],
          getLabel: (value) => value == "webdav"
              ? "backup-destination-webdav".tr()
              : "backup-destination-server".tr(),
          onChanged: (value) async {
            await updateSettings("backupTarget", value,
                updateGlobalState: false);
            setState(() {
              backupTarget = value;
            });
          },
        ),
        AnimatedExpanded(
          expand: backupTarget == "webdav",
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: 10),
            child: Column(
              children: [
                TextInput(
                  labelText: "webdav-url".tr(),
                  controller: webdavUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  padding: EdgeInsetsDirectional.zero,
                ),
                SizedBox(height: 10),
                TextInput(
                  labelText: "webdav-username".tr(),
                  controller: webdavUsernameController,
                  autocorrect: false,
                  padding: EdgeInsetsDirectional.zero,
                ),
                SizedBox(height: 10),
                TextInput(
                  labelText: "webdav-password".tr(),
                  controller: webdavPasswordController,
                  obscureText: true,
                  autocorrect: false,
                  padding: EdgeInsetsDirectional.zero,
                ),
                SizedBox(height: 10),
                TextInput(
                  labelText: "webdav-folder".tr(),
                  controller: webdavFolderController,
                  autocorrect: false,
                  padding: EdgeInsetsDirectional.zero,
                  onSubmitted: (_) => saveWebdavSettings(),
                ),
                SizedBox(height: 10),
                Button(
                  label: "save".tr(),
                  onTap: saveWebdavSettings,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
