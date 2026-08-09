import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/account/accountSheets.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/iconButtonScaled.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Instance administration: the household's other accounts.
///
/// Replaces the old CLI-only provisioning. Renders nothing at all unless the
/// *cached* profile says this person is an administrator, so its visibility
/// never depends on a live request succeeding.
class AdminUsersSection extends StatefulWidget {
  const AdminUsersSection({super.key});

  @override
  State<AdminUsersSection> createState() => _AdminUsersSectionState();
}

class _AdminUsersSectionState extends State<AdminUsersSection> {
  List<ServerUser>? users;
  bool loading = false;
  bool hidden = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    if (cachedServerProfile?.isAdmin == true) _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    final loaded = await selfHostedListUsers();
    if (!mounted) return;
    if (loaded == null) {
      // A refused list when we believed we were an admin means the cached role
      // is stale (demoted elsewhere). Re-check, and hide rather than showing a
      // section the server will keep refusing.
      final profile = await selfHostedFetchProfile();
      if (!mounted) return;
      if (profile != null && !profile.isAdmin) {
        setState(() {
          hidden = true;
          loading = false;
        });
        return;
      }
      setState(() {
        loading = false;
        errorText = "could-not-load-users".tr();
      });
      return;
    }
    setState(() {
      users = loaded;
      loading = false;
    });
  }

  Future<void> _addUser() async {
    await openBottomSheet(
      context,
      popupWithKeyboard: true,
      PopupFramework(
        title: "add-user".tr(),
        child: _AddUserForm(onCreated: _load),
      ),
    );
  }

  Future<void> _resetPassword(ServerUser user) async {
    await openPopup(
      context,
      title: "reset-password".tr(),
      description: "reset-password-description".tr(
        namedArgs: {"account": user.displayName},
      ),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.key_outlined
          : Icons.key_rounded,
      onCancelLabel: "cancel".tr(),
      onCancel: () => popRoute(context),
      onSubmitLabel: "reset-password".tr(),
      onSubmit: () async {
        popRoute(context);
        final (result, password) = await selfHostedResetUserPassword(user.id);
        if (!mounted) return;
        if (result != ServerCallResult.ok || password == null) {
          openSnackbar(SnackbarMessage(
            title: messageForServerCallResult(result),
            icon: Icons.error_rounded,
          ));
          return;
        }
        await showTemporaryPassword(context, user.email, password);
        await _load();
      },
    );
  }

  Future<void> _deleteUser(ServerUser user) async {
    await openPopup(
      context,
      title: "delete-user".tr(),
      description: "delete-user-description".tr(
        namedArgs: {"account": user.displayName},
      ),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outlined
          : Icons.delete_rounded,
      onCancelLabel: "cancel".tr(),
      onCancel: () => popRoute(context),
      onSubmitLabel: "delete".tr(),
      onSubmit: () async {
        popRoute(context);
        final result = await selfHostedDeleteUser(user.id);
        if (!mounted) return;
        if (result != ServerCallResult.ok) {
          openSnackbar(SnackbarMessage(
            title: messageForServerCallResult(
              result,
              conflictMessage: "cannot-remove-last-administrator".tr(),
            ),
            icon: Icons.error_rounded,
          ));
          return;
        }
        openSnackbar(SnackbarMessage(
          title: "user-deleted".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.delete_outlined
              : Icons.delete_rounded,
        ));
        await _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cachedServerProfile?.isAdmin != true || hidden) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 15),
        SettingsHeader(title: "manage-users".tr()),
        if (loading && users == null)
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: 20),
            child: Center(
              // Inline, never a blocking overlay -- a slow admin list must not
              // stop the rest of the page from being usable.
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (errorText != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 18, vertical: 10),
            child: TextFont(
              text: errorText!,
              textAlign: TextAlign.center,
              textColor: getColor(context, "textLight"),
              maxLines: 3,
            ),
          ),
          SettingsContainer(
            title: "try-again".tr(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.refresh_outlined
                : Icons.refresh_rounded,
            onTap: _load,
          ),
        ] else
          for (final user in users ?? <ServerUser>[])
            SettingsContainer(
              title: user.displayName,
              description: user.name.trim().isEmpty ? null : user.email,
              icon: user.isAdmin
                  ? (appStateSettings["outlinedIcons"]
                      ? Icons.shield_outlined
                      : Icons.shield_rounded)
                  : (appStateSettings["outlinedIcons"]
                      ? Icons.person_outlined
                      : Icons.person_rounded),
              afterWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButtonScaled(
                    tooltip: "reset-password".tr(),
                    iconData: appStateSettings["outlinedIcons"]
                        ? Icons.key_outlined
                        : Icons.key_rounded,
                    iconSize: 20,
                    scale: 1.4,
                    onTap: () => _resetPassword(user),
                  ),
                  // Never offer to delete yourself: it would drop you out of
                  // the only session that could undo it.
                  if (user.id != cachedServerProfile?.id)
                    IconButtonScaled(
                      tooltip: "delete".tr(),
                      iconData: appStateSettings["outlinedIcons"]
                          ? Icons.delete_outlined
                          : Icons.delete_rounded,
                      iconSize: 20,
                      scale: 1.4,
                      onTap: () => _deleteUser(user),
                    ),
                ],
              ),
            ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 18, vertical: 10),
          child: Button(
            label: "add-user".tr(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.person_add_outlined
                : Icons.person_add_rounded,
            onTap: _addUser,
          ),
        ),
      ],
    );
  }
}

/// Shows a freshly-generated password exactly once.
///
/// Not dismissible by tapping outside: the server never stores this in
/// recoverable form, so a stray tap would lose it and force another reset.
Future<void> showTemporaryPassword(
    BuildContext context, String email, String password) async {
  await openPopupCustom(
    context,
    title: "temporary-password".tr(),
    barrierDismissible: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFont(
          text: "temporary-password-description".tr(namedArgs: {"account": email}),
          textAlign: TextAlign.center,
          fontSize: 15,
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: getColor(context, "lightDarkAccentHeavy"),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            password,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: "monospace",
              fontSize: 17,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextFont(
          text: "temporary-password-shown-once".tr(),
          textAlign: TextAlign.center,
          fontSize: 13,
          maxLines: 4,
          textColor: getColor(context, "textLight"),
        ),
        const SizedBox(height: 16),
        Button(
          label: "copy".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.copy_outlined
              : Icons.copy_rounded,
          onTap: () => copyToClipboard(password),
        ),
        const SizedBox(height: 10),
        Button(
          label: "done".tr(),
          onTap: () => popRoute(context),
        ),
      ],
    ),
  );
}

class _AddUserForm extends StatefulWidget {
  const _AddUserForm({required this.onCreated});
  final Future<void> Function() onCreated;

  @override
  State<_AddUserForm> createState() => _AddUserFormState();
}

class _AddUserFormState extends State<_AddUserForm> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final FocusNode emailFocus = FocusNode();

  bool submitting = false;
  String? errorText;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting) return;
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => errorText = "email-required".tr());
      return;
    }
    setState(() {
      submitting = true;
      errorText = null;
    });

    final (result, created) = await selfHostedCreateUser(
      email: email,
      name: nameController.text.trim(),
    );
    if (!mounted) return;

    if (result != ServerCallResult.ok || created == null) {
      setState(() {
        submitting = false;
        errorText = messageForServerCallResult(result);
      });
      return;
    }

    popRoute(context);
    await showTemporaryPassword(context, created.user.email, created.temporaryPassword);
    await widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFont(
          text: "add-user-description".tr(),
          fontSize: 14,
          maxLines: 4,
        ),
        const SizedBox(height: 15),
        TextInput(
          labelText: "their-name".tr(),
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          padding: EdgeInsetsDirectional.zero,
          autoFocus: true,
          onSubmitted: (_) => emailFocus.requestFocus(),
        ),
        const SizedBox(height: 10),
        TextInput(
          labelText: "email".tr(),
          controller: emailController,
          focusNode: emailFocus,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          padding: EdgeInsetsDirectional.zero,
          onSubmitted: (_) => _submit(),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 12),
            child: TextFont(
              text: errorText!,
              textColor: Theme.of(context).colorScheme.error,
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
          ),
        const SizedBox(height: 20),
        Button(label: "add-user".tr(), disabled: submitting, onTap: _submit),
      ],
    );
  }
}
