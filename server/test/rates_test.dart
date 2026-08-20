import 'dart:io';

import 'package:server/src/api.dart';
import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';
import 'package:server/src/rates/rate_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_api.dart';

/// A [TestApi] whose rate table comes from a stub instead of the network.
///
/// [fetches] counts how many times the stub was asked, which is how the
/// caching tests below tell "served from cache" apart from "went and looked".
class RatesApi {
  final TestApi api;
  int fetches = 0;
  Map<String, double>? nextResult;

  RatesApi._(this.api);

  factory RatesApi.create({Duration refreshInterval = const Duration(hours: 6)}) {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys=ON;');
    migrate(db);
    final authService = AuthService(db);
    final dataDir = Directory.systemTemp.createTempSync('cashew-rates-test');
    late final RatesApi self;
    final handler = buildApiRouter(
      authService,
      db,
      dataDir.path,
      rateRefreshInterval: refreshInterval,
      fetchExchangeRates: () async {
        self.fetches++;
        return self.nextResult;
      },
    ).call;
    self = RatesApi._(TestApi.forHandler(db, authService, handler, dataDir));
    self.nextResult = {'usd': 1.0, 'rub': 0.0125, 'dzd': 0.0075};
    return self;
  }

  void dispose() => api.dispose();
}

void main() {
  late RatesApi rates;
  setUp(() => rates = RatesApi.create());
  tearDown(() => rates.dispose());

  Future<Response> get(String token) => rates.api.send('GET', '/rates', token: token);

  group('reading rates', () {
    test('requires a session', () async {
      expect((await rates.api.send('GET', '/rates')).statusCode, 401);
    });

    test('fetches once and serves the same table to every member', () async {
      final admin = await rates.api.setupAdmin();
      final member = await rates.api.addMember(admin, shareHousehold: true);

      final adminBody = await rates.api.json(await get(admin));
      final memberBody = await rates.api.json(await get(member.token));

      // The whole point of the endpoint: the household cannot disagree,
      // because there is only one stored table and one fetch behind it.
      expect(memberBody['rates'], equals(adminBody['rates']));
      expect(adminBody['rates'], containsPair('rub', 0.0125));
      expect(rates.fetches, 1);
    });

    test('serves a member of another dataset the same table', () async {
      // Rates are deployment-wide, not dataset-scoped: an isolated account is
      // still reading the same currencies.
      final admin = await rates.api.setupAdmin();
      final solo = await rates.api.addMember(admin, email: 'solo@example.com');
      expect((await rates.api.json(await get(solo.token)))['rates'],
          equals((await rates.api.json(await get(admin)))['rates']));
    });

    test('says so plainly when it has never managed to fetch', () async {
      // An empty table would read as "every rate is missing", and the app
      // falls back to 1:1 on a missing rate -- which shows rubles as dinars
      // one for one rather than admitting it does not know.
      rates.nextResult = null;
      final admin = await rates.api.setupAdmin();
      expect((await get(admin)).statusCode, 503);
    });

    test('keeps serving the last good table after a failed refresh', () async {
      final admin = await rates.api.setupAdmin();
      await get(admin);

      rates.nextResult = null;
      // Force the cache stale so the next read triggers a refresh that fails.
      rates.api.db.execute('UPDATE exchange_rates SET fetched_at = 0');
      final response = await get(admin);

      expect(response.statusCode, 200);
      expect((await rates.api.json(response))['rates'], containsPair('rub', 0.0125),
          reason: 'a failed refresh must never blank the table');
    });
  });

  group('overrides', () {
    test('an administrator sets one and everyone reads it', () async {
      final admin = await rates.api.setupAdmin();
      final member = await rates.api.addMember(admin, shareHousehold: true);

      expect(
          (await rates.api.send('PUT', '/rates/overrides/rub',
                  body: {'rate': 0.011}, token: admin))
              .statusCode,
          200);

      final body = await rates.api.json(await get(member.token));
      expect(body['rates'], containsPair('rub', 0.011),
          reason: 'the override is folded in server-side, once, for everybody');
      expect(body['overrides'], containsPair('rub', 0.011));
      expect(body['rates'], containsPair('dzd', 0.0075),
          reason: 'an override for one currency must not disturb the others');
    });

    test('a household member cannot set one', () async {
      final admin = await rates.api.setupAdmin();
      final member = await rates.api.addMember(admin, shareHousehold: true);
      expect(
          (await rates.api.send('PUT', '/rates/overrides/rub',
                  body: {'rate': 0.011}, token: member.token))
              .statusCode,
          403);
    });

    test('rejects a rate that would break every conversion', () async {
      final admin = await rates.api.setupAdmin();
      for (final bad in [0, -1, 'nonsense']) {
        expect(
            (await rates.api.send('PUT', '/rates/overrides/rub',
                    body: {'rate': bad}, token: admin))
                .statusCode,
            400,
            reason: 'the app divides by a rate, so $bad poisons the whole household');
      }
    });

    test('removing one falls back to the fetched value', () async {
      final admin = await rates.api.setupAdmin();
      await rates.api
          .send('PUT', '/rates/overrides/rub', body: {'rate': 0.011}, token: admin);
      await rates.api.send('DELETE', '/rates/overrides/rub', token: admin);

      final body = await rates.api.json(await get(admin));
      expect(body['rates'], containsPair('rub', 0.0125));
      expect(body['overrides'], isEmpty);
    });
  });

  group('caching', () {
    test('does not refetch while the table is fresh', () async {
      final admin = await rates.api.setupAdmin();
      await get(admin);
      await get(admin);
      await get(admin);
      expect(rates.fetches, 1);
    });

    test('refetches once the interval has passed', () async {
      final admin = await rates.api.setupAdmin();
      await get(admin);
      rates.api.db.execute('UPDATE exchange_rates SET fetched_at = 0');
      rates.nextResult = {'usd': 1.0, 'rub': 0.0130, 'dzd': 0.0075};

      // The stale read is served from cache and refreshes behind the response,
      // so the new value lands on the read after it.
      await get(admin);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rates.fetches, 2);
      expect((await rates.api.json(await get(admin)))['rates'],
          containsPair('rub', 0.0130));
    });
  });

  group('reading the published feed', () {
    test('takes the usd table out of the real response shape', () {
      final parsed = parseExchangeRateFeed(
          '{"date":"2026-08-20","usd":{"rub":80.4,"dzd":134.2}}');
      expect(parsed, equals({'rub': 80.4, 'dzd': 134.2}));
    });

    test('drops values that would poison a conversion', () {
      // The app divides by a rate. A zero, a negative or a non-number must be
      // left out rather than stored and served to the whole household.
      final parsed = parseExchangeRateFeed(
          '{"usd":{"rub":80.4,"aaa":0,"bbb":-3,"ccc":"nonsense"}}');
      expect(parsed, equals({'rub': 80.4}));
    });

    test('returns null on anything it cannot use', () {
      expect(parseExchangeRateFeed('not json'), isNull);
      expect(parseExchangeRateFeed('[]'), isNull);
      expect(parseExchangeRateFeed('{"date":"2026-08-20"}'), isNull);
      expect(parseExchangeRateFeed('{"usd":{}}'), isNull);
    });
  });
}
