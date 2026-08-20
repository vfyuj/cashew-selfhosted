import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'dart:convert';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> currenciesJSON = {};

loadCurrencyJSON() async {
  currenciesJSON = await json.decode(
      await rootBundle.loadString('assets/static/generated/currencies.json'));
}

/// The published feed, used only when there is no server to ask.
///
/// Kept as the signed-out path on purpose: per specs/01-local-first-invariant.md
/// the app has to be fully usable with no server and no account, and a solo
/// install still has multiple currencies to convert between.
const String publishedExchangeRateUrl =
    "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json";

/// Which currencies an administrator has pinned by hand, deployment-wide.
///
/// Mirrored from the last `GET /rates` purely so the rates screen can show
/// which values were set rather than fetched. Never consulted when converting:
/// the server has already folded overrides into the table it served, so the
/// conversion path has one source and cannot disagree with itself.
Map<String, double> serverRateOverrides = {};

/// Refreshes the currency table.
///
/// **Signed in, the table comes from this deployment's own server**, so every
/// member of a household converts the same transaction the same way. It did not
/// used to: each device fetched the feed itself into device-local settings, and
/// two devices that last launched on different days disagreed about every figure
/// that crossed a currency. See docs/server/rates.md.
///
/// Never throws and never blocks anything. A failure leaves the previously
/// stored table exactly where it was -- stale rates draw slightly old numbers,
/// while no rates at all would draw badly wrong ones (see
/// [getCurrencyExchangeRate]).
Future<bool> getExchangeRates() async {
  if (selfHostedSession != null) {
    final ServerExchangeRates? served = await selfHostedFetchRates();
    if (served != null && served.rates.isNotEmpty) {
      serverRateOverrides = served.overrides;
      await _storeExchangeRates(served.rates);
      await _handOverLocalOverrides();
      return true;
    }
    // Deliberately no fall-through to the published feed here. Reaching past
    // an unreachable server to the CDN is how devices drift apart again: two
    // of them would be back to holding independently-fetched tables, which is
    // the bug this endpoint exists to remove. Keep the last served table.
    print("Could not reach the server for exchange rates; keeping the stored table");
    return false;
  }

  // No account: nothing to agree with, so the published feed it is.
  try {
    final response = await http
        .get(Uri.parse(publishedExchangeRateUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return false;
    final usd = decoded["usd"];
    if (usd is! Map) return false;
    await _storeExchangeRates({
      for (final entry in usd.entries)
        if (entry.value is num) entry.key.toString(): (entry.value as num).toDouble()
    });
    return true;
  } catch (e) {
    print("Error getting currency rates: " + e.toString());
    return false;
  }
}

/// Moves any rates this device had pinned by hand up to the server, once.
///
/// Overrides used to live in device-local settings, which made them a second
/// way for a household to disagree: one member pinning a rate changed only
/// their own figures. They belong to the deployment now.
///
/// Only an administrator's are moved, and only theirs are cleared afterwards.
/// Anyone else's are left exactly where they are: they are already inert for
/// any currency the server knows (see [getCurrencyExchangeRate]), and they are
/// the *only* record of a user-defined currency's rate, so deleting them would
/// throw away something nothing else holds. Self-limiting for the
/// administrator: it clears the map, so later calls do nothing.
Future<void> _handOverLocalOverrides() async {
  final Map<dynamic, dynamic> local = appStateSettings["customCurrencyAmounts"];
  if (local.isEmpty) return;
  if (cachedServerProfile?.isAdmin != true) return;

  for (final entry in local.entries) {
    final value = entry.value;
    if (value is! num || !value.isFinite || value <= 0) continue;
    final result =
        await selfHostedSetRateOverride(entry.key.toString(), value.toDouble());
    // Leave the map alone if even one failed to land, so the next launch
    // retries rather than silently discarding what someone typed.
    if (result != ServerCallResult.ok) {
      print("Could not hand over the rate override for ${entry.key}");
      return;
    }
  }

  // The server's table already includes them now, so re-read it rather than
  // waiting a whole refresh interval to show what was just uploaded.
  final ServerExchangeRates? refreshed = await selfHostedFetchRates();
  if (refreshed != null && refreshed.rates.isNotEmpty) {
    serverRateOverrides = refreshed.overrides;
    await _storeExchangeRates(refreshed.rates);
  }

  await updateSettings("customCurrencyAmounts", {}, updateGlobalState: false);
}

/// Writes a fetched table into settings, redrawing only when it changed.
///
/// An empty table is refused rather than stored: [getCurrencyExchangeRate]
/// treats a missing currency as a rate of 1, so blanking the table would show
/// every foreign amount at par instead of admitting it does not know.
Future<void> _storeExchangeRates(Map<String, double> rates) async {
  if (rates.isEmpty) return;
  final Map<dynamic, dynamic> stored = appStateSettings["cachedCurrencyExchange"];
  // Redraw when the numbers actually moved. Previously this only refreshed the
  // UI when the table had been empty, so a rate that changed under a running
  // app was stored but not shown until something else forced a rebuild.
  final bool changed = json.encode(stored) != json.encode(rates);
  await updateSettings(
    "cachedCurrencyExchange",
    rates,
    updateGlobalState: changed,
  );
}

double amountRatioToPrimaryCurrencyGivenPk(
  AllWallets allWallets,
  String walletPk, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (allWallets.indexedByPk[walletPk] == null) return 1;
  return amountRatioToPrimaryCurrency(
    allWallets,
    allWallets.indexedByPk[walletPk]?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
}

double amountRatioToPrimaryCurrency(
  AllWallets allWallets,
  String? walletCurrency, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (walletCurrency == null) {
    return 1;
  }
  if (allWallets
          .indexedByPk[
              (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
          ?.currency ==
      walletCurrency) {
    return 1;
  }
  if (allWallets.indexedByPk[
          (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]] ==
      null) {
    return 1;
  }

  double exchangeRateFromUSDToTarget = getCurrencyExchangeRate(
    allWallets
        .indexedByPk[
            (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
        ?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
  double exchangeRateFromCurrentToUSD = 1 /
      getCurrencyExchangeRate(
        walletCurrency,
        appStateSettingsPassed: appStateSettingsPassed,
      );
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

double? amountRatioFromToCurrency(
    String walletCurrencyBefore, String walletCurrencyAfter) {
  double exchangeRateFromUSDToTarget =
      getCurrencyExchangeRate(walletCurrencyAfter);
  double exchangeRateFromCurrentToUSD =
      1 / getCurrencyExchangeRate(walletCurrencyBefore);
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

// assume selected wallets currency
String getCurrencyString(AllWallets allWallets, {String? currencyKey}) {
  String? selectedWalletCurrency =
      allWallets.indexedByPk[appStateSettings["selectedWalletPk"]]?.currency;
  return currencyKey != null
      ? (currenciesJSON[currencyKey]?["Symbol"] ?? "")
      : selectedWalletCurrency == null
          ? ""
          : (currenciesJSON[selectedWalletCurrency]?["Symbol"] ?? "");
}

/// Whether [currencyKey] has a known rate at all.
///
/// Worth asking before showing a converted figure. [getCurrencyExchangeRate]
/// answers 1 for a currency it has never heard of, which is indistinguishable
/// from a currency genuinely at par with the primary one -- so a device that
/// has never reached the server draws rubles as dinars one for one rather than
/// admitting it does not know. Callers that can say "not available" should.
bool isCurrencyExchangeRateKnown(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return true;
  final settings = appStateSettingsPassed ?? appStateSettings;
  return settings["customCurrencyAmounts"]?[currencyKey] != null ||
      settings["cachedCurrencyExchange"]?[currencyKey] != null;
}

double getCurrencyExchangeRate(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return 1;
  final settings = appStateSettingsPassed ?? appStateSettings;
  final dynamic pinned = settings["customCurrencyAmounts"]?[currencyKey];
  final dynamic served = settings["cachedCurrencyExchange"]?[currencyKey];

  // Which of the two wins depends on whether there is a server, and the order
  // is the whole fix. Signed in, the served table already has the deployment's
  // overrides folded into it, so letting a device-local pin sit on top is
  // precisely how two devices start disagreeing again -- see
  // docs/server/rates.md.
  //
  // The local map is still consulted second, and that is not a leftover: a
  // user-defined currency (appStateSettings["customCurrencies"]) exists only
  // there, because no published feed has ever heard of it. Preferring the
  // served table for currencies it knows, and falling back for ones it does
  // not, keeps both working.
  if (selfHostedSession == null) {
    if (pinned != null) return pinned.toDouble();
    if (served != null) return served.toDouble();
  } else {
    if (served != null) return served.toDouble();
    if (pinned != null) return pinned.toDouble();
  }
  return 1;
}

double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget) {
  return budget.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk));
}

double objectiveAmountToPrimaryCurrency(
    AllWallets allWallets, Objective objective) {
  return objective.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, objective.walletFk));
}

double categoryBudgetLimitToPrimaryCurrency(
    AllWallets allWallets, CategoryBudgetLimit limit) {
  return limit.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, limit.walletFk));
}

double envelopeAmountToPrimaryCurrency(
    AllWallets allWallets, CategoryEnvelope envelope) {
  return envelope.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, envelope.walletFk));
}

// Positive (input)
double getAmountRatioWalletTransferTo(AllWallets allWallets, String walletToPk,
    {String? enteredAmountWalletPk}) {
  return amountRatioFromToCurrency(
        allWallets
            .indexedByPk[
                enteredAmountWalletPk ?? appStateSettings["selectedWalletPk"]]!
            .currency!,
        allWallets.indexedByPk[walletToPk]!.currency!,
      ) ??
      1;
}

// Negative (output)
double getAmountRatioWalletTransferFrom(
    AllWallets allWallets, String walletFromPk,
    {String? enteredAmountWalletPk}) {
  return -1 *
      (amountRatioFromToCurrency(
            allWallets
                .indexedByPk[enteredAmountWalletPk ??
                    appStateSettings["selectedWalletPk"]]!
                .currency!,
            allWallets.indexedByPk[walletFromPk]!.currency!,
          ) ??
          1);
}
