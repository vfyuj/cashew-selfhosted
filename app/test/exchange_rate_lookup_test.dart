import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which rate wins, and what happens when there is no rate at all.
///
/// These are pure lookups over a settings map, so they run without a database,
/// a server or a signed-in session -- [getCurrencyExchangeRate] takes the map
/// as `appStateSettingsPassed`, which is the seam this file uses.
///
/// The bug behind all of it: rates used to be fetched per device into
/// device-local settings, so two devices in one household converted the same
/// shared transaction differently. The server now serves one table with any
/// administrator override already folded in. See docs/server/rates.md.
void main() {
  Map<String, dynamic> settings({
    Map<String, dynamic>? served,
    Map<String, dynamic>? pinned,
  }) =>
      {
        "cachedCurrencyExchange": served ?? <String, dynamic>{},
        "customCurrencyAmounts": pinned ?? <String, dynamic>{},
      };

  group('signed out', () {
    // No session in a unit test, so this is the branch these exercise.
    test('uses the fetched table', () {
      expect(
        getCurrencyExchangeRate('rub',
            appStateSettingsPassed: settings(served: {'rub': 80.4})),
        80.4,
      );
    });

    test('a pinned rate wins, because there is no server holding one', () {
      expect(
        getCurrencyExchangeRate('rub',
            appStateSettingsPassed:
                settings(served: {'rub': 80.4}, pinned: {'rub': 79.0})),
        79.0,
      );
    });

    test('a user-defined currency lives only in the pinned map', () {
      // No published feed has heard of it, so the pinned map is the only
      // record of what it is worth.
      expect(
        getCurrencyExchangeRate('mycoin',
            appStateSettingsPassed:
                settings(served: {'rub': 80.4}, pinned: {'mycoin': 12.0})),
        12.0,
      );
    });
  });

  group('an unknown currency', () {
    test('still answers 1, which is why callers should ask first', () {
      // Kept as-is deliberately: every caller treats the return as a usable
      // number. What changed is that there is now a way to tell "at par" from
      // "never heard of it" before showing a figure.
      expect(getCurrencyExchangeRate('zzz', appStateSettingsPassed: settings()), 1);
      expect(
        isCurrencyExchangeRateKnown('zzz', appStateSettingsPassed: settings()),
        isFalse,
        reason: 'a device that never reached the server must not silently '
            'draw rubles as dinars one for one',
      );
    });

    test('reports a currency it does know', () {
      expect(
        isCurrencyExchangeRateKnown('rub',
            appStateSettingsPassed: settings(served: {'rub': 80.4})),
        isTrue,
      );
      expect(
        isCurrencyExchangeRateKnown('mycoin',
            appStateSettingsPassed: settings(pinned: {'mycoin': 12.0})),
        isTrue,
      );
    });

    test('an empty or absent key is treated as the primary currency', () {
      expect(getCurrencyExchangeRate(null, appStateSettingsPassed: settings()), 1);
      expect(getCurrencyExchangeRate('', appStateSettingsPassed: settings()), 1);
      expect(isCurrencyExchangeRateKnown(null, appStateSettingsPassed: settings()),
          isTrue);
    });
  });

  group('two devices reading one household', () {
    test('agree once they are reading the same served table', () {
      // The regression this whole change exists to prevent: the same served
      // table has to produce the same number on both devices, whatever either
      // one happens to have pinned locally from before.
      final phone = settings(served: {'rub': 80.4}, pinned: {'rub': 79.0});
      final laptop = settings(served: {'rub': 80.4});

      // Signed out, the phone's stale pin still wins -- correct, there is no
      // server to defer to, and nothing shared to break.
      expect(getCurrencyExchangeRate('rub', appStateSettingsPassed: phone), 79.0);
      expect(getCurrencyExchangeRate('rub', appStateSettingsPassed: laptop), 80.4);

      // Once the pin is handed over, both read the served table. The signed-in
      // ordering is covered by server/test/rates_test.dart, which owns the
      // "everyone gets the same table" guarantee.
      final handedOver = settings(served: {'rub': 80.4});
      expect(getCurrencyExchangeRate('rub', appStateSettingsPassed: handedOver),
          getCurrencyExchangeRate('rub', appStateSettingsPassed: laptop));
    });
  });
}
