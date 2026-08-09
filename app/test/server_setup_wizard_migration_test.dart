import 'dart:convert';

import 'package:cashew_selfhosted/struct/databaseGlobal.dart';
import 'package:cashew_selfhosted/struct/defaultPreferences.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the one change in this feature that can regress silently for every
/// existing user at once.
///
/// getUserSettings() merges any missing default key into stored settings on
/// launch, so `hasCompletedServerSetup: false` reaches installs that onboarded
/// long ago. Without the migration, updating the app would drop those people
/// into a first-run "set up this server" wizard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> givenStoredSettings(Map<String, dynamic> stored) async {
    SharedPreferences.setMockInitialValues(
        {'userSettings': json.encode(stored)});
    sharedPreferences = await SharedPreferences.getInstance();
    // Mirrors initializeSettings(): defaults first, then whatever was stored.
    appStateSettings = {...await getDefaultPreferences(), ...stored};
    selfHostedSession = null;
  }

  Map<String, dynamic> persistedSettings() =>
      json.decode(sharedPreferences.getString('userSettings')!)
          as Map<String, dynamic>;

  group('attemptToMigrateServerSetupWizard', () {
    test('an install that already onboarded never sees the wizard', () async {
      await givenStoredSettings({'hasOnboarded': true});

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isTrue);
      expect(persistedSettings()['hasCompletedServerSetup'], isTrue,
          reason: 'must be written immediately, not left for a later save');
    });

    test('an install that is signed in never sees the wizard', () async {
      // Onboarding predates this flag, so a long-lived install can plausibly
      // have hasSignedIn without hasOnboarded having been recorded.
      await givenStoredSettings({'hasOnboarded': false, 'hasSignedIn': true});

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isTrue);
    });

    test('an install with a live session never sees the wizard', () async {
      await givenStoredSettings({'hasOnboarded': false, 'hasSignedIn': false});
      selfHostedSession = SelfHostedSession(
        serverUrl: 'https://example.test',
        email: 'owner@example.test',
        sessionToken: 'token',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isTrue);
    });

    test('a genuinely fresh install still gets the wizard', () async {
      await givenStoredSettings({'hasOnboarded': false, 'hasSignedIn': false});

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isFalse);
      expect(appStateSettings['migratedServerSetupWizard'], isTrue,
          reason: 'the marker is set either way, so this runs exactly once');
    });

    test('does not re-run and cannot undo a later skip', () async {
      await givenStoredSettings({'hasOnboarded': false, 'hasSignedIn': false});
      await attemptToMigrateServerSetupWizard();

      // The user then skips the wizard, or completes it.
      appStateSettings['hasCompletedServerSetup'] = true;
      // ...and later signs out entirely.
      appStateSettings['hasSignedIn'] = false;

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isTrue,
          reason: 'a second run must not push the user back into the wizard');
    });

    test('is safe when settings are unexpectedly empty', () async {
      await givenStoredSettings({});

      await attemptToMigrateServerSetupWizard();

      expect(appStateSettings['hasCompletedServerSetup'], isFalse);
    });
  });
}
