import 'package:cashew_selfhosted/struct/budgetPeriodAmounts.dart';
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

Future<bool> getExchangeRates() async {
  print("Getting exchange rates for current wallets");
  // List<String?> uniqueCurrencies =
  //     await database.getUniqueCurrenciesFromWallets();
  Map<dynamic, dynamic> cachedCurrencyExchange =
      appStateSettings["cachedCurrencyExchange"];
  try {
    Uri url = Uri.parse(
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json");
    dynamic response = await http.get(url);
    if (response.statusCode == 200) {
      cachedCurrencyExchange = json.decode(response.body)?["usd"];
    }
  } catch (e) {
    print("Error getting currency rates: " + e.toString());
    return false;
  }
  // print(cachedCurrencyExchange);
  updateSettings(
    "cachedCurrencyExchange",
    cachedCurrencyExchange,
    updateGlobalState:
        appStateSettings["cachedCurrencyExchange"].keys.length <= 0,
  );
  return true;
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

double getCurrencyExchangeRate(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return 1;
  if ((appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
          ?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
            [currencyKey]
        .toDouble();
  } else if ((appStateSettingsPassed ??
          appStateSettings)["cachedCurrencyExchange"]?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ??
            appStateSettings)["cachedCurrencyExchange"][currencyKey]
        .toDouble();
  } else {
    return 1;
  }
}

// Pass [forDate] when rendering a specific budget period, so a period that has
// already finished keeps the target it was measured against at the time rather
// than picking up whatever the budget is set to now. Omitting it reads the
// current amount, which is the right answer for anything about "now" (planned
// totals, goal entry) and a safe default everywhere else.
double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget,
    {DateTime? forDate}) {
  final double amount = forDate == null
      ? budget.amount
      : budgetAmountForPeriod(budget, forDate);
  return amount *
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
