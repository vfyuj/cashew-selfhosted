import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/database/tables.dart';
import 'package:cashew_selfhosted/pages/aboutPage.dart';
import 'package:cashew_selfhosted/pages/addTransactionPage.dart';
import 'package:cashew_selfhosted/struct/currencyFunctions.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:cashew_selfhosted/widgets/button.dart';
import 'package:cashew_selfhosted/widgets/fadeIn.dart';
import 'package:cashew_selfhosted/widgets/framework/popupFramework.dart';
import 'package:cashew_selfhosted/widgets/noResults.dart';
import 'package:cashew_selfhosted/widgets/framework/pageFramework.dart';
import 'package:cashew_selfhosted/widgets/openBottomSheet.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/outlinedButtonStacked.dart';
import 'package:cashew_selfhosted/widgets/selectAmount.dart';
import 'package:cashew_selfhosted/widgets/statusBox.dart';
import 'package:cashew_selfhosted/widgets/tappable.dart';
import 'package:cashew_selfhosted/widgets/textInput.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cashew_selfhosted/main.dart';
import 'package:provider/provider.dart';
import 'package:cashew_selfhosted/functions.dart';
import 'package:cashew_selfhosted/struct/settings.dart';

/// Whether this device may change what a currency is worth.
///
/// Signed out, a pinned rate is device-local and there is nobody to disagree
/// with, so anyone may set one. Signed in, the rate table belongs to the
/// deployment and only an administrator edits it -- otherwise one member
/// pinning a rate would put the household's figures back out of step, which is
/// the whole reason the server holds them. See docs/server/rates.md.
bool get canEditExchangeRates =>
    selfHostedSession == null || cachedServerProfile?.isAdmin == true;

/// The rate pinned by hand for [currencyKey], or null if it is simply the
/// fetched one.
///
/// Reads from wherever the pins actually live: the deployment's own list when
/// signed in, this device's settings when not. One accessor, so the screen's
/// highlighting and its number pad cannot end up describing different maps.
double? pinnedExchangeRate(String currencyKey) {
  if (selfHostedSession != null) return serverRateOverrides[currencyKey];
  final dynamic local = appStateSettings["customCurrencyAmounts"]?[currencyKey];
  return local is num ? local.toDouble() : null;
}

class ExchangeRates extends StatefulWidget {
  const ExchangeRates({super.key});

  @override
  State<ExchangeRates> createState() => _ExchangeRatesState();
}

class _ExchangeRatesState extends State<ExchangeRates> {
  String searchCurrenciesText = "";

  Future addCustomCurrency(String customKey) async {
    List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
    customCurrencies.add(customKey);
    await updateSettings(
      "customCurrencies",
      customCurrencies,
      updateGlobalState: false,
    );
    setState(() {});
  }

  Future<DeletePopupAction?> deleteCustomCurrency(String customKey) async {
    DeletePopupAction? action = await openDeletePopup(
      context,
      title: "delete-currency-question".tr(),
      subtitle: customKey,
    );
    if (action == DeletePopupAction.Delete) {
      List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
      customCurrencies.remove(customKey);
      await updateSettings(
        "customCurrencies",
        customCurrencies,
        updateGlobalState: false,
      );
      Map<dynamic, dynamic> customCurrencyAmountsMap =
          appStateSettings["customCurrencyAmounts"];
      customCurrencyAmountsMap.remove(customKey);
      updateSettings("customCurrencyAmounts", customCurrencyAmountsMap,
          updateGlobalState: false);
      setState(() {});
    }
    return action;
  }

  @override
  Widget build(BuildContext context) {
    Map<dynamic, dynamic> currencyExchange = {};
    List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
    for (String key in customCurrencies) {
      currencyExchange[key] = null;
    }
    currencyExchange.addAll(appStateSettings["cachedCurrencyExchange"]);
    // No table at all: a device that has never reached the server, or never had
    // a network. Every currency below is then drawn at 1, which is a real
    // number for a currency at par and a badly wrong one for every other -- so
    // say so rather than letting the list read as fact. See the note above
    // isCurrencyExchangeRateKnown in struct/currencyFunctions.dart.
    final bool ratesUnavailable = currencyExchange.keys.length <= 0;
    if (ratesUnavailable) {
      for (String key in currenciesJSON.keys) {
        currencyExchange[key] = 1;
      }
    }

    // else {
    //   for (String key in [...customCurrencies, ...currencyExchange.keys]) {
    //     if (currenciesJSON.keys.contains(key) == false) {
    //       currencyExchange.remove(key);
    //     }
    //   }
    // }
    Map<dynamic, dynamic> currencyExchangeFiltered = {};
    if (searchCurrenciesText == "") {
      currencyExchangeFiltered = currencyExchange;
    } else {
      for (String key in currencyExchange.keys) {
        String? currencyCountry = currenciesJSON[key]?["CountryName"];
        String? currencyName = currenciesJSON[key]?["Currency"];
        if ((searchCurrenciesText.trim() == "" ||
            key.toLowerCase().contains(searchCurrenciesText.toLowerCase()) ||
            (currencyCountry != null &&
                currencyCountry
                    .toLowerCase()
                    .contains(searchCurrenciesText.toLowerCase())) ||
            (currencyName != null &&
                currencyName
                    .toLowerCase()
                    .contains(searchCurrenciesText.toLowerCase())))) {
          currencyExchangeFiltered[key] = currencyExchange[key];
        }
      }
    }

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      title: "exchange-rates".tr(),
      actions: [
        IconButton(
          padding: EdgeInsetsDirectional.all(15),
          tooltip: "info".tr(),
          onPressed: () {
            openPopup(
              context,
              title: "exchange-rate-notice".tr(),
              description: "exchange-rate-notice-description".tr() +
                  "\n\n" +
                  "select-an-entry-to-set-custom-exchange-rate".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.info_outlined
                  : Icons.info_outline_rounded,
              onCancel: () {
                popRoute(context);
              },
              onCancelLabel: "ok".tr(),
            );
          },
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.info_outlined
                : Icons.info_outline_rounded,
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: AboutInfoBox(
            title: "exchange-rates-api".tr(),
            link: "https://github.com/fawazahmed0/exchange-api",
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: 5),
            child: Row(
              children: [
                SizedBox(width: 15),
                Expanded(
                  child: TextInput(
                    labelText: "search-currencies-placeholder".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.search_outlined
                        : Icons.search_rounded,
                    onChanged: (value) {
                      setState(() {
                        searchCurrenciesText = value;
                      });
                    },
                    autoFocus: false,
                    padding: EdgeInsetsDirectional.zero,
                  ),
                ),
                SizedBox(width: 10),
                ButtonIcon(
                  onTap: () {
                    openBottomSheet(
                      context,
                      popupWithKeyboard: true,
                      PopupFramework(
                        title: "add-currency".tr(),
                        child: SelectText(
                          buttonLabel: "add-currency".tr(),
                          icon: appStateSettings["outlinedIcons"]
                              ? Icons.account_balance_wallet_outlined
                              : Icons.account_balance_wallet_rounded,
                          setSelectedText: (_) {},
                          nextWithInput: (text) async {
                            addCustomCurrency(text);
                          },
                          selectedText: "",
                          placeholder: "currency".tr(),
                          autoFocus: true,
                        ),
                      ),
                    );
                  },
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.add_outlined
                      : Icons.add_rounded,
                ),
                SizedBox(width: 15),
              ],
            ),
          ),
        ),
        if (ratesUnavailable)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 13, vertical: 8),
              child: StatusBox(
                title: "exchange-rates-unavailable".tr(),
                description: "exchange-rates-unavailable-description".tr(),
                color: Theme.of(context).colorScheme.error,
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_off_rounded,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: 5),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 17),
              child: TextFont(
                text: "select-an-entry-to-set-custom-exchange-rate".tr(),
                maxLines: 2,
                fontSize: 13,
                textColor: getColor(context, "textLight"),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: 7),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 17, vertical: 5),
              child: TextFont(
                text: "1 " +
                    Provider.of<AllWallets>(context)
                        .indexedByPk[appStateSettings["selectedWalletPk"]]!
                        .currency
                        .toString()
                        .allCaps,
                maxLines: 2,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        currencyExchangeFiltered.keys.length == 0
            ? SliverToBoxAdapter(
                child: NoResults(message: "no-currencies-found".tr()),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    String key = currencyExchangeFiltered.keys
                        .toList()[index]
                        .toString();
                    bool isCustomCurrency = customCurrencies.contains(key);
                    bool isUnsetCustomCurrency =
                        isCustomCurrency && pinnedExchangeRate(key) == null;
                    String calculatedExchangeRateString = isUnsetCustomCurrency
                        ? "1"
                        : (1 /
                                ((amountRatioToPrimaryCurrency(
                                    Provider.of<AllWallets>(context), key))))
                            .toStringAsFixed(14);
                    return ScaledAnimatedSwitcher(
                      keyToWatch: pinnedExchangeRate(key).toString(),
                      key: ValueKey(key),
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                            bottom: isCustomCurrency ? 5 : 0),
                        child: Tappable(
                          onTap: () async {
                            if (!canEditExchangeRates) {
                              openSnackbar(SnackbarMessage(
                                title: "rates-are-shared".tr(),
                                description: "rates-are-shared-description".tr(),
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.info_outlined
                                    : Icons.info_rounded,
                              ));
                              return;
                            }
                            await openBottomSheet(
                              context,
                              SetCustomCurrency(currencyKey: key),
                            );
                            setState(() {});
                          },
                          color: isCustomCurrency ||
                                  pinnedExchangeRate(key) == null
                              ? Colors.transparent
                              : Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                          child: Padding(
                            padding:
                                EdgeInsetsDirectional.symmetric(horizontal: 8),
                            child: OutlinedContainer(
                              enabled: isCustomCurrency,
                              filled: pinnedExchangeRate(key) != null,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.symmetric(
                                    horizontal: 7),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextFont(
                                        text: "",
                                        maxLines: 3,
                                        richTextSpan: [
                                          TextSpan(
                                            text: (isUnsetCustomCurrency
                                                    ? " " + "1 USD"
                                                    : "") +
                                                " = " +
                                                calculatedExchangeRateString,
                                            style: TextStyle(
                                              color: getColor(context, "black"),
                                              fontFamily:
                                                  appStateSettings["font"],
                                              fontFamilyFallback: ['Inter'],
                                              fontSize: 16,
                                            ),
                                          ),
                                          TextSpan(
                                            text: " " + key.allCaps,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontFamily:
                                                  appStateSettings["font"],
                                              fontFamilyFallback: ['Inter'],
                                              color: getColor(context, "black"),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isCustomCurrency)
                                      IconButton(
                                        padding: EdgeInsetsDirectional.all(15),
                                        tooltip: "delete-currency".tr(),
                                        onPressed: () {
                                          deleteCustomCurrency(key);
                                        },
                                        icon: Icon(
                                          appStateSettings["outlinedIcons"]
                                              ? Icons.delete_outlined
                                              : Icons.delete_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: currencyExchangeFiltered.keys.length,
                ),
              ),
      ],
    );
  }
}

class SetCustomCurrency extends StatefulWidget {
  const SetCustomCurrency({required this.currencyKey, super.key});
  final String currencyKey;

  @override
  State<SetCustomCurrency> createState() => _SetCustomCurrencyState();
}

class _SetCustomCurrencyState extends State<SetCustomCurrency> {
  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "set-currency".tr(),
      // subtitle: "1 " +
      //     Provider.of<AllWallets>(context)
      //         .indexedByPk[appStateSettings["selectedWalletPk"]]!
      //         .currency
      //         .toString()
      //         .allCaps +
      //     " = ",
      subtitle: "1 USD = ",
      child: SelectAmountValue(
        allowZero: true,
        setSelectedAmount: (amount, amountString) async {
          final bool clearing = amount == 0 || amountString == "";

          // Signed in, an override belongs to the deployment: it goes to the
          // server, which folds it into the table it serves everyone. Writing
          // it locally as well would give this device a second, competing
          // answer -- see docs/server/rates.md.
          if (selfHostedSession != null) {
            final result = clearing
                ? await selfHostedClearRateOverride(widget.currencyKey)
                : await selfHostedSetRateOverride(widget.currencyKey, amount);
            if (result != ServerCallResult.ok) {
              openSnackbar(SnackbarMessage(
                title: "rate-not-saved".tr(),
                description: "server-unreachable".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_off_rounded,
              ));
              return;
            }
            // Pull the new table straight back, so the figure on screen is the
            // one the household will see rather than the one before the edit.
            await getExchangeRates();
            appStateKey.currentState?.refreshAppState();
            return;
          }

          Map<dynamic, dynamic> customCurrencyAmountsMap =
              appStateSettings["customCurrencyAmounts"];
          if (clearing) {
            customCurrencyAmountsMap.remove(widget.currencyKey);
          } else {
            // This will convert the primary currency to the custom currency
            // Issue: the selected currency may change, causing the custom currency to change
            // That is why we only allow the user to set the exchange rate of USD! since it is our reference
            // E.g. primary currency CAD, set custom currency of EUR to 5, then USD->CAD exchange rate changes when it's
            // pulled (the CAD exchange rate entry), the exchange rate for EUR will change, since it references USD!
            // double currentExchangeRate = getCurrencyExchangeRate(
            //     Provider.of<AllWallets>(context, listen: false)
            //         .indexedByPk[appStateSettings["selectedWalletPk"]]!
            //         .currency);
            // customCurrencyAmountsMap[widget.currencyKey] =
            //     currentExchangeRate * amount;
            customCurrencyAmountsMap[widget.currencyKey] = amount;
          }
          updateSettings("customCurrencyAmounts", customCurrencyAmountsMap,
              updateGlobalState: false);
        },
        // Convert amount passed into selected primary currency, read above why disabled
        // amountPassed: appStateSettings["customCurrencyAmounts"]
        //             ?[widget.currencyKey] ==
        //         null
        //     ? ""
        //     : removeTrailingZeroes((1 /
        //             getCurrencyExchangeRate(
        //                 (Provider.of<AllWallets>(context, listen: false)
        //                     .indexedByPk[appStateSettings["selectedWalletPk"]]!
        //                     .currency)) *
        //             (appStateSettings["customCurrencyAmounts"]
        //                     ?[widget.currencyKey] ??
        //                 1))
        //         .toString()),
        amountPassed: pinnedExchangeRate(widget.currencyKey) == null
            ? ""
            : removeTrailingZeroes(
                pinnedExchangeRate(widget.currencyKey).toString()),
        suffix: " " + widget.currencyKey.allCaps,
        nextLabel: "set-amount".tr(),
        next: () {
          popRoute(context);
        },
      ),
    );
  }
}

String? originalExchangeRatesBeforeOpenString;
void checkIfExchangeRateChangeBefore() {
  originalExchangeRatesBeforeOpenString =
      appStateSettings["customCurrencyAmounts"].toString();
}

bool checkIfExchangeRateChangeAfter() {
  // print(originalExchangeRatesBeforeOpenString);
  // print(appStateSettings["customCurrencyAmounts"].toString());
  if (originalExchangeRatesBeforeOpenString != null &&
      originalExchangeRatesBeforeOpenString !=
          appStateSettings["customCurrencyAmounts"].toString()) {
    print("There was a change to the custom currencies!");
    // Reset global state because currencies need to be reloaded
    appStateKey.currentState?.refreshAppState();
    originalExchangeRatesBeforeOpenString = null;
    return true;
  } else {
    return false;
  }
}
