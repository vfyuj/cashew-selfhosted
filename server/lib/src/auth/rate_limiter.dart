import 'dart:io';

import 'package:shelf/shelf.dart';

/// Per-client attempt limiting for the unauthenticated password endpoints.
///
/// Why this exists: verifying a password is bcrypt, which is *deliberately*
/// expensive -- a few hundred milliseconds on a modest server. Without a limit,
/// anyone who can reach `/auth/login` can queue up unbounded bcrypt work with
/// nothing but a loop and no credentials. Password guessing is the lesser
/// worry; burning the box's CPU is the real one.
///
/// A sliding window rather than a fixed one, so an attacker can't get a double
/// burst by straddling a window boundary.
class RateLimiter {
  /// Attempts allowed per key per [window].
  final int limit;
  final Duration window;

  /// Distinct keys tracked before a sweep is forced. Bounds memory against
  /// someone cycling source addresses purely to grow this map.
  final int maxTrackedKeys;

  final Map<String, List<int>> _hits = {};

  RateLimiter({
    required this.limit,
    required this.window,
    this.maxTrackedKeys = 10000,
  });

  /// Records an attempt for [key], returning false when it should be refused.
  bool allow(String key, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final cutoff = nowMs - window.inMilliseconds;

    if (_hits.length >= maxTrackedKeys) _sweep(cutoff);

    final hits = _hits.putIfAbsent(key, () => <int>[]);
    hits.removeWhere((at) => at <= cutoff);
    if (hits.length >= limit) return false;
    hits.add(nowMs);
    return true;
  }

  /// Seconds until [key] frees up. Only meaningful right after [allow]
  /// returned false; used for the `Retry-After` header.
  int retryAfterSeconds(String key, {DateTime? now}) {
    final hits = _hits[key];
    if (hits == null || hits.isEmpty) return 0;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final freesAt = hits.first + window.inMilliseconds;
    final seconds = ((freesAt - nowMs) / 1000).ceil();
    return seconds < 1 ? 1 : seconds;
  }

  void _sweep(int cutoff) {
    _hits.removeWhere((_, hits) {
      hits.removeWhere((at) => at <= cutoff);
      return hits.isEmpty;
    });
  }
}

/// Whether `X-Forwarded-For` is believed. Defaults to true because
/// DEPLOYMENT.md's deployment model puts this server behind Nginx Proxy
/// Manager -- and there, every request arrives from the proxy's own address,
/// so without this the whole household shares one bucket and a single flood
/// locks everyone out. Set `TRUST_PROXY_HEADER=false` when the server is
/// exposed directly, where the header is attacker-controlled.
final bool _trustProxyHeader =
    (Platform.environment['TRUST_PROXY_HEADER'] ?? 'true').toLowerCase() != 'false';

/// Best-effort client identity for rate limiting.
///
/// Takes the **rightmost** `X-Forwarded-For` entry, not the leftmost. nginx
/// appends the peer it actually saw to whatever the client sent
/// (`proxy_add_x_forwarded_for`), so with one proxy in front the last entry is
/// the only one the client couldn't forge. The leftmost -- the conventional
/// "real client IP" -- is entirely client-supplied and trivially rotated.
String clientKeyOf(Request request) {
  if (_trustProxyHeader) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null) {
      final parts = forwarded
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty);
      if (parts.isNotEmpty) return parts.last;
    }
  }
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}

/// Wraps a handler so it refuses with 429 once [limiter] is exhausted for the
/// caller. Applied per route rather than as blanket middleware -- only the
/// endpoints that run bcrypt need it, and putting it on `/auth/refresh` would
/// throttle ordinary sync traffic.
Handler rateLimited(RateLimiter limiter, Handler inner) {
  return (Request request) async {
    final key = clientKeyOf(request);
    if (!limiter.allow(key)) {
      return Response(
        429,
        body: '{"error":"too many attempts, try again shortly"}',
        headers: {
          'content-type': 'application/json',
          'retry-after': '${limiter.retryAfterSeconds(key)}',
        },
      );
    }
    return await inner(request);
  };
}
