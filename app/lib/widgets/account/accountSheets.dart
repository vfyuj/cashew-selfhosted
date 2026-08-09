import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services show TextInput;

/// Shared error wording, so every account form says the same thing about the
/// same failure.
String messageForServerCallResult(ServerCallResult result,
    {String? conflictMessage}) {
  switch (result) {
    case ServerCallResult.invalidCredentials:
      return "invalid-login".tr();
    case ServerCallResult.forbidden:
      return "administrator-access-required".tr();
    case ServerCallResult.conflict:
      return conflictMessage ?? "email-already-in-use".tr();
    case ServerCallResult.validationError:
      return "password-too-short".tr();
    case ServerCallResult.unreachable:
      return "server-unreachable".tr();
    default:
      return "server-error".tr();
  }
}

Future<void> openEditProfileSheet(BuildContext context) async {
  await openBottomSheet(
    context,
    popupWithKeyboard: true,
    PopupFramework(
      title: "edit-profile".tr(),
      child: const _EditProfileForm(),
    ),
  );
}

class _EditProfileForm extends StatefulWidget {
  const _EditProfileForm();

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  late final TextEditingController nameController =
      TextEditingController(text: cachedServerProfile?.name ?? "");
  late final TextEditingController emailController = TextEditingController(
      text: cachedServerProfile?.email ??
          (appStateSettings["currentUserEmail"] ?? "").toString());
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

    final result = await selfHostedUpdateProfile(
      name: nameController.text.trim(),
      email: email,
    );
    if (!mounted) return;

    if (result != ServerCallResult.ok) {
      setState(() {
        submitting = false;
        errorText = messageForServerCallResult(result);
      });
      return;
    }

    refreshUIAfterLoginChange();
    popRoute(context);
    openSnackbar(SnackbarMessage(
      title: "profile-updated".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.check_circle_outlined
          : Icons.check_circle_rounded,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextInput(
                labelText: "your-name".tr(),
                controller: nameController,
                autofillHints: const [AutofillHints.name],
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
                autofillHints: const [AutofillHints.username],
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                padding: EdgeInsetsDirectional.zero,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
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
        Button(label: "save".tr(), disabled: submitting, onTap: _submit),
      ],
    );
  }
}

Future<void> openChangePasswordSheet(BuildContext context) async {
  await openBottomSheet(
    context,
    popupWithKeyboard: true,
    PopupFramework(
      title: "change-password".tr(),
      child: const _ChangePasswordForm(),
    ),
  );
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm();

  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final TextEditingController currentController = TextEditingController();
  final TextEditingController newController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  final FocusNode newFocus = FocusNode();
  final FocusNode confirmFocus = FocusNode();

  bool submitting = false;
  String? errorText;

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    newFocus.dispose();
    confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting) return;
    if (currentController.text.isEmpty) {
      setState(() => errorText = "password-required".tr());
      return;
    }
    if (newController.text.length < 8) {
      setState(() => errorText = "password-too-short".tr());
      return;
    }
    if (newController.text != confirmController.text) {
      setState(() => errorText = "passwords-do-not-match".tr());
      return;
    }
    setState(() {
      submitting = true;
      errorText = null;
    });

    final result = await selfHostedChangePassword(
      currentPassword: currentController.text,
      newPassword: newController.text,
    );
    if (!mounted) return;

    if (result != ServerCallResult.ok) {
      setState(() {
        submitting = false;
        errorText = result == ServerCallResult.invalidCredentials
            ? "incorrect-current-password".tr()
            : messageForServerCallResult(result);
      });
      return;
    }

    minimizeKeyboard(context);
    await Future.delayed(const Duration(milliseconds: 50));
    services.TextInput.finishAutofillContext(shouldSave: true);
    if (!mounted) return;

    popRoute(context);
    openSnackbar(SnackbarMessage(
      title: "password-changed".tr(),
      description: "other-devices-signed-out".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.lock_outlined
          : Icons.lock_rounded,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final accountEmail = cachedServerProfile?.email ??
        (appStateSettings["currentUserEmail"] ?? "").toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Read-only, but present on purpose: without a username field in
              // the form, most password managers save a second, orphaned entry
              // instead of updating the existing one.
              TextInput(
                labelText: "email".tr(),
                initialValue: accountEmail,
                readOnly: true,
                autofillHints: const [AutofillHints.username],
                padding: EdgeInsetsDirectional.zero,
              ),
              const SizedBox(height: 10),
              TextInput(
                labelText: "current-password".tr(),
                controller: currentController,
                autofillHints: const [AutofillHints.password],
                obscureText: true,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.next,
                padding: EdgeInsetsDirectional.zero,
                autoFocus: true,
                onSubmitted: (_) => newFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              TextInput(
                labelText: "new-password".tr(),
                controller: newController,
                focusNode: newFocus,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: true,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.next,
                padding: EdgeInsetsDirectional.zero,
                onSubmitted: (_) => confirmFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              // No autofill hint: the web engine derives the DOM id from the
              // hint, so a second newPassword field would collide.
              TextInput(
                labelText: "confirm-password".tr(),
                controller: confirmController,
                focusNode: confirmFocus,
                obscureText: true,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.done,
                padding: EdgeInsetsDirectional.zero,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
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
        const SizedBox(height: 12),
        TextFont(
          text: "change-password-signs-out-other-devices".tr(),
          fontSize: 13,
          textAlign: TextAlign.center,
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        Button(
          label: "change-password".tr(),
          disabled: submitting,
          onTap: _submit,
        ),
      ],
    );
  }
}
