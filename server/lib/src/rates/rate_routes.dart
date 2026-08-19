import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';


/// Where the rates come from. USD-based, which is why nothing here rebases
/// them: the app's own conversion maths already works in "units per USD".
const exchangeRateSourceUrl =
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json';

/// How stale the cached table may get before the next request refreshes it.
///
/// Household budgeting does not need intraday rates, and the point of this
/// endpoint is that everyone agrees rather than that everyone is current --
/// so this is deliberately long enough that a household's devices see one
/// value for most of a day.
const defaultRateRefreshInterval = Duration(hours: 6);

/// Reads the published feed's body, or null if it is not usable.
///
/// Separate from the fetch so the shape can be tested without the network. The
/// feed is `{"date": "...", "usd": {"rub": 80.4, ...}}`; anything else, and any
/// individual value that is not a usable positive number, is dropped rather
/// than trusted -- a zero or a negative would divide through the whole
/// household's conversions.
Map<String, double>? parseExchangeRateFeed(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final usd = decoded['usd'];
    if (usd is! Map) return null;
    final rates = <String, double>{};
    for (final entry in usd.entries) {
      final value = entry.value;
      if (value is num && value.isFinite && value > 0) {
        rates[entry.key.toString()] = value.toDouble();
      }
    }
    return rates.isEmpty ? null : rates;
  } catch (e) {
    print('Could not read the exchange rate feed: $e');
    return null;
  }
}

/// Fetches the published table, or null if it could not be read.
///
/// Returning null rather than throwing is the contract the router relies on:
/// a failed refresh must leave the last good table in place, never surface as
/// an error to a client that only wanted to draw a number.
Future<Map<String, double>?> fetchExchangeRatesFromSource() async {
  try {
    final response = await http
        .get(Uri.parse(exchangeRateSourceUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    return parseExchangeRateFeed(response.body);
  } catch (e) {
    print('Could not fetch exchange rates: $e');
    return null;
  }
}

/// Deployment-wide currency rates, so every member of a household converts the
/// same transaction the same way.
///
/// This is not dataset-scoped and not user-scoped. A rate is not data anyone
/// owns -- it is how everyone's data is read -- and the bug that motivated this
/// endpoint was exactly the mismatch: rates lived in device-local settings, so
/// two devices that last launched on different days showed the same shared
/// transaction as two different amounts. See docs/server/rates.md.
///
/// [fetchRates] and [refreshInterval] are injectable so tests never touch the
/// network.
Router buildRatesRouter(
  Database db, {
  Future<Map<String, double>?> Function()? fetchRates,
  Duration refreshInterval = defaultRateRefreshInterval,
}) {
  final router = Router();
  final fetch = fetchRates ?? fetchExchangeRatesFromSource;

  // Guards against a burst of clients each starting their own refresh when the
  // cache goes stale: the first one through takes the trip, the rest read what
  // is already stored.
  Future<void>? inFlight;

  ({Map<String, double> rates, int fetchedAt})? readCached() {
    final rows = db.select('SELECT rates, fetched_at FROM exchange_rates WHERE id = 0');
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['rates'] as String);
      if (decoded is! Map) return null;
      return (
        rates: {
          for (final entry in decoded.entries)
            if (entry.value is num) entry.key.toString(): (entry.value as num).toDouble()
        },
        fetchedAt: rows.first['fetched_at'] as int,
      );
    } catch (e) {
      // A corrupt cache is treated as no cache: the next refresh replaces it.
      print('Stored exchange rates could not be read: $e');
      return null;
    }
  }

  Map<String, double> readOverrides() {
    return {
      for (final row in db.select('SELECT currency, rate FROM exchange_rate_overrides'))
        row['currency'] as String: (row['rate'] as num).toDouble()
    };
  }

  Future<void> refresh() async {
    final rates = await fetch();
    // A failed fetch deliberately leaves fetched_at alone, so the next request
    // tries again instead of waiting out the interval on a table nobody got.
    if (rates == null) return;
    db.execute(
      'INSERT INTO exchange_rates (id, rates, fetched_at) VALUES (0, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET rates = excluded.rates, fetched_at = excluded.fetched_at',
      [jsonEncode(rates), DateTime.now().millisecondsSinceEpoch],
    );
  }

  // Errors are swallowed here, not propagated: this is called without being
  // awaited on the stale-but-usable path, where an escaping error becomes an
  // unhandled async error and takes the isolate down for a failure whose only
  // consequence is that the rates stay one refresh older.
  Future<void> refreshOnce() {
    final existing = inFlight;
    if (existing != null) return existing;
    final started = refresh().catchError((Object e) {
      print('Exchange rate refresh failed: $e');
    }).whenComplete(() => inFlight = null);
    inFlight = started;
    return started;
  }

  router.get('/', (Request request) async {
    var cached = readCached();

    if (cached == null) {
      // Nothing to serve, so this one request waits for the trip. Every later
      // one has something to fall back on.
      await refreshOnce();
      cached = readCached();
    } else {
      final age = DateTime.now().millisecondsSinceEpoch - cached.fetchedAt;
      if (age >= refreshInterval.inMilliseconds) {
        // Stale but present: refresh behind this response rather than making
        // the caller wait for a CDN round trip to redraw a screen.
        unawaited(refreshOnce());
      }
    }

    if (cached == null) {
      // The server has never managed to fetch. Say so plainly instead of
      // returning an empty table, which a client would read as "every rate is
      // missing" and quietly fall back to 1:1.
      return Response(
        503,
        body: jsonEncode({'error': 'exchange rates are not available yet'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final overrides = readOverrides();
    // Overrides are folded in here rather than on each device, so "what this
    // deployment believes a currency is worth" has exactly one answer. The raw
    // override map still ships alongside, so the rates screen can show which
    // values were set by hand.
    final effective = {...cached.rates, ...overrides};
    return Response.ok(
      jsonEncode({
        'rates': effective,
        'overrides': overrides,
        'fetchedAt': cached.fetchedAt,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
