import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:cashew_selfhosted/pages/addTransactionPage.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/account/accountProfileSection.dart';
import 'package:cashew_selfhosted/widgets/account/adminUsersSection.dart';
import 'package:cashew_selfhosted/widgets/account/serverCredentialsForm.dart';
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
  const AccountsPage({Key? key, this.isPushedRoute = false}) : super(key: key);

  /// True when opened as its own pushed route rather than as page 8 of the
  /// navigation framework. A pushed route must close itself once the user is
  /// signed in -- callers like [signInAndSync] await the pop, and a page that
  /// merely swapped to its signed-in view would leave them waiting forever.
  /// That is the bug that used to strand onboarding with a dead sidebar.
  final bool isPushedRoute;

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  bool currentlyExporting = false;

  void refreshState() {
    setState(() {});
  }

  Future<void> _signOut() async {
    final result = await selfHostedLogout();
    if (result == true && mounted) {
      // currentState is null whenever PageNavigationFramework isn't mounted --
      // during onboarding, and during the first-run wizard. It used to be
      // force-unwrapped here, which threw instead of signing out.
      final navigationState = pageNavigationFrameworkKey.currentState;
      if (getIsFullScreen(context) == false || navigationState == null) {
        maybePopRoute(context);
        settingsPageStateKey.currentState?.refreshState();
      } else {
        navigationState.changePage(0, switchNavbar: true);
      }
    }
    refreshUIAfterLoginChange();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: getPlatform() == PlatformOS.isIOS
          ? "my-account".tr()
          : "my-account".tr(),
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
                        // The same form the first-run wizard uses, so someone
                        // who skipped the wizard gets an identical experience
                        // here -- including "set up this server" if the
                        // instance still has no accounts.
                        ServerCredentialsForm(
                          mode: ServerAuthMode.signIn,
                          popOnSuccess: widget.isPushedRoute,
                          onSuccess: refreshState,
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AccountProfileSection(onSignOut: _signOut),
                      const AdminUsersSection(),
                      SizedBox(height: 10),
                      SettingsHeader(title: "backups".tr()),
                      SizedBox(height: 10),
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
                                  openSyncSettings(context);
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
