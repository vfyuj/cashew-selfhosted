import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/iconButtonScaled.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Imported prefixed and narrowed on purpose: this app has its own TextInput
// widget, and an unprefixed services import would make the name ambiguous
// everywhere below. `services.TextInput` is only needed for the one static
// finishAutofillContext call; everything else (AutofillHints, TextCapitalization)
// already arrives via material.dart.
import 'package:flutter/services.dart' as services show TextInput;

enum ServerAuthMode {
  /// Sign in to an instance that already has accounts.
  signIn,

  /// Create the instance's first account, which becomes its administrator.
  setup,
}

/// The credential form, shared by the first-run wizard and the account page.
///
/// Deliberately one widget rather than two: the wizard and the account page
/// must agree about autofill wiring, error wording and what "success" does, and
/// two copies would drift. Callers vary the behaviour through the flags below
/// instead of reimplementing the form.
class ServerCredentialsForm extends StatefulWidget {
  const ServerCredentialsForm({
    super.key,
    required this.mode,
    this.initialServerUrl,
    this.showServerUrlField = !kIsWeb,
    this.runSyncAfterLogin = true,
    this.popOnSuccess = false,
    this.onSuccess,
    this.onSetupUnavailable,
    this.footer,
  });

  final ServerAuthMode mode;
  final String? initialServerUrl;

  /// On web the app is served from its own API's origin, so there is exactly
  /// one correct server URL and asking for it is only a chance to get it wrong.
  final bool showServerUrlField;

  /// The wizard passes false. Syncing there can reach `restartAppPopup`, which
  /// dims and disables the whole UI -- unusable on a screen that has no
  /// navigation yet. The main app already runs the cloud functions on its first
  /// mount, so nothing is skipped by waiting.
  final bool runSyncAfterLogin;

  /// True when hosted in a pushed route or sheet that should close itself once
  /// the user is signed in. Without this a caller awaiting the route's pop
  /// waits forever -- the bug that used to strand onboarding.
  final bool popOnSuccess;

  final VoidCallback? onSuccess;

  /// Called when a setup attempt is refused because the instance already has
  /// accounts, so the host can switch itself to sign-in.
  final VoidCallback? onSetupUnavailable;

  /// Rendered under the submit button, e.g. the wizard's "use without an
  /// account" escape.
  final Widget? footer;

  @override
  State<ServerCredentialsForm> createState() => ServerCredentialsFormState();
}

class ServerCredentialsFormState extends State<ServerCredentialsForm> {
  late final TextEditingController serverUrlController = TextEditingController(
      text: widget.initialServerUrl ??
          (kIsWeb ? Uri.base.origin : appStateSettings["serverUrl"] ?? ""));
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();
  final FocusNode confirmFocus = FocusNode();

  bool submitting = false;
  bool passwordVisible = false;
  String? errorText;

  bool get isSetup => widget.mode == ServerAuthMode.setup;

  @override
  void dispose() {
    for (final controller in [
      serverUrlController,
      nameController,
      emailController,
      passwordController,
      confirmController
    ]) {
      controller.dispose();
    }
    for (final node in [nameFocus, emailFocus, passwordFocus, confirmFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (widget.showServerUrlField && serverUrlController.text.trim().isEmpty) {
      return "server-url-required".tr();
    }
    if (emailController.text.trim().isEmpty) return "email-required".tr();
    if (passwordController.text.isEmpty) return "password-required".tr();
    if (isSetup) {
      if (passwordController.text.length < 8) return "password-too-short".tr();
      if (passwordController.text != confirmController.text) {
        return "passwords-do-not-match".tr();
      }
    }
    return null;
  }

  String _messageFor(ServerCallResult result) {
    switch (result) {
      case ServerCallResult.invalidCredentials:
        return "invalid-login".tr();
      case ServerCallResult.unreachable:
        return "server-unreachable".tr();
      case ServerCallResult.validationError:
        return "password-too-short".tr();
      case ServerCallResult.conflict:
        return isSetup ? "server-already-set-up".tr() : "email-already-in-use".tr();
      default:
        return "server-error".tr();
    }
  }

  Future<void> submit() async {
    if (submitting) return;
    final validationError = _validate();
    if (validationError != null) {
      setState(() => errorText = validationError);
      return;
    }
    setState(() {
      submitting = true;
      errorText = null;
    });

    // On web the controller is pre-filled with Uri.base.origin and the field
    // is hidden, so this is correct whether or not it was shown.
    final serverUrl = serverUrlController.text;
    final email = emailController.text.trim();

    final result = isSetup
        ? await selfHostedSetup(
            serverUrl: serverUrl,
            email: email,
            name: nameController.text.trim(),
            password: passwordController.text,
          )
        : await selfHostedLoginDetailed(
            serverUrl: serverUrl,
            email: email,
            password: passwordController.text,
          );

    if (!mounted) return;

    if (result != ServerCallResult.ok) {
      setState(() {
        submitting = false;
        errorText = _messageFor(result);
      });
      // Someone else claimed this instance between the probe and the submit.
      // Let the host flip to sign-in rather than leaving a dead form.
      if (isSetup && result == ServerCallResult.conflict) {
        widget.onSetupUnavailable?.call();
      }
      return;
    }

    // Detach the input connection before committing, so the browser has the
    // form registered by the time the save prompt is requested.
    minimizeKeyboard(context);
    await Future.delayed(const Duration(milliseconds: 50));
    services.TextInput.finishAutofillContext(shouldSave: true);

    if (widget.runSyncAfterLogin && mounted) {
      await syncAfterLogin(context);
    }
    refreshUIAfterLoginChange();

    if (!mounted) return;
    widget.onSuccess?.call();
    if (widget.popOnSuccess && mounted) popRoute(context, true);
  }

  Widget _passwordVisibilityToggle() {
    // On Flutter web the autofill hint is applied to the DOM element *after*
    // obscureText, and it forces type="password" on any password-hinted field.
    // The toggle would flip its own icon and change nothing, so don't show one.
    if (kIsWeb) return const SizedBox.shrink();
    return IconButtonScaled(
      iconData: passwordVisible
          ? (appStateSettings["outlinedIcons"]
              ? Icons.visibility_off_outlined
              : Icons.visibility_off_rounded)
          : (appStateSettings["outlinedIcons"]
              ? Icons.visibility_outlined
              : Icons.visibility_rounded),
      iconSize: 20,
      scale: 1.4,
      tooltip: passwordVisible ? "hide-password".tr() : "show-password".tr(),
      onTap: () => setState(() => passwordVisible = !passwordVisible),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kept outside the AutofillGroup on purpose: the emitted web form
        // should contain exactly the username and password fields, which is
        // what browser login heuristics look for.
        if (widget.showServerUrlField) ...[
          TextInput(
            labelText: "server-url".tr(),
            controller: serverUrlController,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            padding: EdgeInsetsDirectional.zero,
            onSubmitted: (_) =>
                (isSetup ? nameFocus : emailFocus).requestFocus(),
          ),
          const SizedBox(height: 10),
        ],
        AutofillGroup(
          // The default is `commit`, which fires the browser's "save password?"
          // prompt even when the user backs out. Commit explicitly on success
          // instead -- see submit().
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSetup) ...[
                TextInput(
                  labelText: "your-name".tr(),
                  controller: nameController,
                  focusNode: nameFocus,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  padding: EdgeInsetsDirectional.zero,
                  onSubmitted: (_) => emailFocus.requestFocus(),
                ),
                const SizedBox(height: 10),
              ],
              TextInput(
                labelText: "email".tr(),
                controller: emailController,
                focusNode: emailFocus,
                // Not AutofillHints.email: `autocomplete="username"` is what
                // login-form detection keys on, and an email fills it fine.
                // Only the first hint reaches the web engine anyway.
                autofillHints: const [AutofillHints.username],
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                padding: EdgeInsetsDirectional.zero,
                onSubmitted: (_) => passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              TextInput(
                labelText: "password".tr(),
                controller: passwordController,
                focusNode: passwordFocus,
                autofillHints: [
                  isSetup ? AutofillHints.newPassword : AutofillHints.password
                ],
                obscureText: !passwordVisible,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction:
                    isSetup ? TextInputAction.next : TextInputAction.done,
                padding: EdgeInsetsDirectional.zero,
                suffixWidget: _passwordVisibilityToggle(),
                onSubmitted: (_) =>
                    isSetup ? confirmFocus.requestFocus() : submit(),
              ),
              if (isSetup) ...[
                const SizedBox(height: 10),
                TextInput(
                  labelText: "confirm-password".tr(),
                  controller: confirmController,
                  focusNode: confirmFocus,
                  // No autofill hint on purpose. The web engine derives the DOM
                  // id and name from the hint, so a second newPassword field
                  // would collide with the first inside the same form.
                  obscureText: !passwordVisible,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  padding: EdgeInsetsDirectional.zero,
                  onSubmitted: (_) => submit(),
                ),
              ],
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
              maxLines: 4,
            ),
          ),
        const SizedBox(height: 20),
        Button(
          label: isSetup ? "create-admin-account".tr() : "sign-in-to-server".tr(),
          disabled: submitting,
          onTap: submit,
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 12),
          widget.footer!,
        ],
      ],
    );
  }
}
