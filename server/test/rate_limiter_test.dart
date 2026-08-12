import 'dart:convert';

import 'package:server/src/auth/rate_limiter.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The limiter exists so an unauthenticated caller can't queue unbounded
/// bcrypt work on the server's single event loop. Time is injected
/// throughout rather than slept through, so these stay instant and
/// deterministic.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('RateLimiter', () {
    test('allows up to the limit, then refuses', () {
      final limiter = RateLimiter(limit: 3, window: const Duration(minutes: 5));

      expect(limiter.allow('ip', now: t0), isTrue);
      expect(limiter.allow('ip', now: t0), isTrue);
      expect(limiter.allow('ip', now: t0), isTrue);
      expect(limiter.allow('ip', now: t0), isFalse);
    });

    test('keeps separate budgets per key', () {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 5));

      expect(limiter.allow('first', now: t0), isTrue);
      expect(limiter.allow('first', now: t0), isFalse);
      // One noisy client must not lock the rest of the household out.
      expect(limiter.allow('second', now: t0), isTrue);
    });

    test('the window slides rather than resetting on a boundary', () {
      final limiter = RateLimiter(limit: 2, window: const Duration(minutes: 5));

      expect(limiter.allow('ip', now: t0), isTrue);
      expect(limiter.allow('ip', now: t0.add(const Duration(minutes: 4))), isTrue);
      expect(limiter.allow('ip', now: t0.add(const Duration(minutes: 4))), isFalse);

      // The first attempt has now aged out, so exactly one slot frees up --
      // a fixed window would have handed back both here.
      final justAfter = t0.add(const Duration(minutes: 5, seconds: 1));
      expect(limiter.allow('ip', now: justAfter), isTrue);
      expect(limiter.allow('ip', now: justAfter), isFalse);
    });

    test('reports how long until the caller frees up', () {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 5));

      limiter.allow('ip', now: t0);
      expect(limiter.allow('ip', now: t0.add(const Duration(minutes: 1))), isFalse);
      expect(
        limiter.retryAfterSeconds('ip', now: t0.add(const Duration(minutes: 1))),
        240,
      );
    });

    test('sweeps stale keys so the map cannot grow without bound', () {
      // maxTrackedKeys is the trigger, not a hard cap: once tripped, anything
      // whose attempts have aged out of the window is dropped.
      final limiter = RateLimiter(
        limit: 1,
        window: const Duration(minutes: 5),
        maxTrackedKeys: 50,
      );

      for (var i = 0; i < 50; i++) {
        limiter.allow('stale-$i', now: t0);
      }
      final later = t0.add(const Duration(minutes: 10));
      expect(limiter.allow('fresh', now: later), isTrue);
      // Every earlier key aged out and was reclaimed, so a repeat of one is
      // treated as a first attempt again.
      expect(limiter.allow('stale-0', now: later), isTrue);
    });
  });

  group('rateLimited handler', () {
    Handler alwaysOk() => (_) => Response.ok('served');

    test('passes through under the limit and 429s over it', () async {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 5));
      final handler = rateLimited(limiter, alwaysOk());
      Request req() => Request('POST', Uri.parse('http://localhost/auth/login'));

      expect((await handler(req())).statusCode, 200);

      final refused = await handler(req());
      expect(refused.statusCode, 429);
      expect(refused.headers['retry-after'], isNotNull);
      expect(jsonDecode(await refused.readAsString()), containsPair('error', isA<String>()));
    });

    test('separates callers by the rightmost X-Forwarded-For entry', () async {
      // nginx appends the peer it actually saw, so the last entry is the only
      // one a client cannot forge. A client that pre-seeds the header to look
      // like someone else must not be able to spend their budget.
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 5));
      final handler = rateLimited(limiter, alwaysOk());

      Request from(String header) => Request(
            'POST',
            Uri.parse('http://localhost/auth/login'),
            headers: {'x-forwarded-for': header},
          );

      expect((await handler(from('203.0.113.5'))).statusCode, 200);
      expect((await handler(from('203.0.113.5'))).statusCode, 429);
      // Same forged prefix, different real peer -- gets its own budget.
      expect((await handler(from('203.0.113.5, 198.51.100.9'))).statusCode, 200);
    });
  });
}
