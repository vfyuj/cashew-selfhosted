import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/struct/languageMap.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/account/serverCredentialsForm.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:cashew_selfhosted/widgets/viewAllTransactionsButton.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Lets [ServerSetupWizardPage] force this gate to re-evaluate
/// `hasCompletedServerSetup` immediately, rather than relying solely on the
/// app-wide `appStateKey.currentState?.refreshAppState()` cascade.
///
/// This gate sits directly under `MaterialApp.home` (see the class comment
/// below) rather than inside an explicit `Navigator` like
/// `InitialPageRouteNavigator`. In testing, a rebuild triggered from there did
/// not reliably reach this position live -- the flag was correctly persisted
/// (a reload always picked it up) but the wizard stayed on screen until then.
/// A direct, targeted `setState` via this key sidesteps that entirely, the
/// same pattern already used for `sidebarStateKey` and `accountsPageStateKey`.
GlobalKey<_ServerSetupWizardGateState> serverSetupWizardGateKey = GlobalKey();

/// Decides whether the first-run server wizard is showing.
///
/// Mounted in main.dart's outermost Stack rather than inside
/// InitialPageRouteNavigator, because that navigator lives in an Expanded
/// beside NavigationSidebar -- anything rendered there leaves the dimmed,
/// inert sidebar visible alongside it. This sits above the whole Row instead
/// and covers the window, while leaving navigatorKey and snackbarKey mounted
/// underneath so the app's navigation and snackbar helpers keep working.
class ServerSetupWizardGate extends StatefulWidget {
  const ServerSetupWizardGate({super.key});

  @override
  State<ServerSetupWizardGate> createState() => _ServerSetupWizardGateState();
}

class _ServerSetupWizardGateState extends State<ServerSetupWizardGate> {
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (appStateSettings["hasCompletedServerSetup"] == true) {
      return const SizedBox.shrink();
    }
    return const ServerSetupWizardPage();
  }
}

enum _WizardStep {
  /// Native builds: ask which server to talk to.
  serverUrl,

  /// Asking the server whether it has any accounts yet.
  probing,

  /// It has none -- this person is creating the administrator account.
  setup,

  /// It already has accounts -- sign in to an existing one.
  signIn,

  /// We could not reach it. Never fatal; the skip path is still offered.
  unreachable,
}

/// Shown once, before onboarding, on a fresh install.
///
/// Whoever opens a self-hosted instance for the first time deployed it in order
/// to administer it, so the very first thing they see is either "set up this
/// server" or "sign in" -- not a backup screen buried in settings.
///
/// Per specs/01-local-first-invariant.md this is never a gate: "use without an
/// account" is on every step, no network call is required to render, an
/// unreachable server degrades to an inline message, and someone who skips can
/// still sign in later from the account page.
class ServerSetupWizardPage extends StatefulWidget {
  const ServerSetupWizardPage({super.key});

  @override
  State<ServerSetupWizardPage> createState() => _ServerSetupWizardPageState();
}

class _ServerSetupWizardPageState extends State<ServerSetupWizardPage> {
  late final TextEditingController serverUrlController = TextEditingController(
      text: kIsWeb
          ? Uri.base.origin
          : (appStateSettings["serverUrl"] ?? "").toString());

  late _WizardStep step = kIsWeb ? _WizardStep.probing : _WizardStep.serverUrl;
  bool showAdvancedServerUrl = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // On web the app is served from its own API's origin, so there is nothing
      // to ask. Launched off the first frame rather than awaited in build() --
      // the UI must paint from local state with no network on the critical path.
      Future.microtask(_probe);
    }
  }

  @override
  void dispose() {
    serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() => step = _WizardStep.probing);
    final needsSetup = await selfHostedSetupState(serverUrlController.text);
    // The user can hit "use without an account" while this is in flight.
    if (!mounted) return;
    setState(() {
      step = needsSetup == null
          ? _WizardStep.unreachable
          : needsSetup
              ? _WizardStep.setup
              : _WizardStep.signIn;
    });
  }

  /// Leaves the wizard for good. Used by both the skip path and a successful
  /// sign-in, so there is exactly one way out.
  Future<void> _finish() async {
    await updateSettings("hasCompletedServerSetup", true,
        updateGlobalState: true);
    // Belt-and-suspenders: force the gate to re-check the flag right now,
    // rather than trusting the app-wide refresh cascade alone to reach it.
    serverSetupWizardGateKey.currentState?.refresh();
  }

  /// Leaves the wizard after a successful sign-in or setup.
  ///
  /// `hasOnboarded` is a device-local setting, so without this every device
  /// added to an existing account walked its owner through onboarding again --
  /// asking them to create accounts, categories and a budget that were already
  /// sitting on the server waiting to sync down. If the account already holds
  /// data, this device has nothing to set up, so onboarding is marked done.
  ///
  /// The check is best-effort by design: if the server can't answer, onboarding
  /// runs, which is skippable in one tap and creates nothing unless the user
  /// fills something in.
  Future<void> _finishAfterAuth() async {
    // Reuse the probing UI while the check is in flight -- the credentials form
    // has already re-enabled itself by the time it calls back, so without this
    // the wizard would sit there looking idle for a network round-trip.
    if (mounted) setState(() => step = _WizardStep.probing);
    if (await selfHostedAccountHasExistingData()) {
      await updateSettings("hasOnboarded", true, updateGlobalState: false);
    }
    await _finish();
  }

  Widget _heading(String title, String description) {
    return Column(
      children: [
        TextFont(
          text: title,
          fontSize: 26,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          maxLines: 4,
        ),
        const SizedBox(height: 10),
        TextFont(
          text: description,
          fontSize: 15,
          textAlign: TextAlign.center,
          maxLines: 8,
        ),
        const SizedBox(height: 25),
      ],
    );
  }

  Widget _serverUrlStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading("connect-to-your-server".tr(),
            "connect-to-your-server-description".tr(namedArgs: {"app": globalAppName})),
        TextInput(
          labelText: "server-url".tr(),
          controller: serverUrlController,
          keyboardType: TextInputType.url,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          padding: EdgeInsetsDirectional.zero,
          onSubmitted: (_) => _probe(),
        ),
        const SizedBox(height: 20),
        Button(label: "continue".tr(), onTap: _probe),
      ],
    );
  }

  Widget _probingStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        TextFont(
          text: "checking-server".tr(),
          fontSize: 15,
          textAlign: TextAlign.center,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _unreachableStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading("server-unreachable".tr(), "server-unreachable-description".tr()),
        Button(label: "try-again".tr(), onTap: _probe),
        const SizedBox(height: 12),
        LowKeyButton(
          onTap: () => setState(() {
            showAdvancedServerUrl = true;
            step = _WizardStep.serverUrl;
          }),
          text: "change-server-url".tr(),
        ),
      ],
    );
  }

  Widget _credentialsStep() {
    final isSetup = step == _WizardStep.setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          isSetup ? "set-up-this-server".tr() : "sign-in-to-server".tr(),
          isSetup
              ? "set-up-this-server-description".tr()
              : "sign-in-to-server-description".tr(),
        ),
        ServerCredentialsForm(
          // Rebuilt when the mode flips, so controllers and autofill state
          // don't carry across between setup and sign-in.
          key: ValueKey(isSetup),
          mode: isSetup ? ServerAuthMode.setup : ServerAuthMode.signIn,
          initialServerUrl: serverUrlController.text,
          showServerUrlField: !kIsWeb && showAdvancedServerUrl,
          // Syncing here can reach restartAppPopup, which dims and disables the
          // UI -- unusable on a screen with no navigation. The main app runs
          // the cloud functions on its first mount anyway.
          runSyncAfterLogin: false,
          onSuccess: _finishAfterAuth,
          onSetupUnavailable: () {
            if (mounted) setState(() => step = _WizardStep.signIn);
          },
        ),
      ],
    );
  }

  Widget _currentStep() {
    switch (step) {
      case _WizardStep.serverUrl:
        return _serverUrlStep();
      case _WizardStep.probing:
        return _probingStep();
      case _WizardStep.unreachable:
        return _unreachableStep();
      case _WizardStep.setup:
      case _WizardStep.signIn:
        return _credentialsStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Opaque, so it covers the sidebar and the page navigator behind it.
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    appStateSettings["outlinedIcons"]
                        ? Icons.cloud_outlined
                        : Icons.cloud_rounded,
                    size: 55,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubicEmphasized,
                    child: _currentStep(),
                  ),
                  const SizedBox(height: 25),
                  // Built unconditionally, outside the step switch, so no step
                  // can accidentally omit the escape hatch that
                  // specs/01-local-first-invariant.md requires.
                  LowKeyButton(
                    onTap: _finish,
                    text: "use-without-an-account".tr(),
                  ),
                  const SizedBox(height: 8),
                  TextFont(
                    text: "use-without-an-account-description".tr(),
                    fontSize: 13,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    textColor: getColor(context, "textLight"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
