import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

/// Administrator-only edits to the rate table, mounted at `/rates/overrides`.
///
/// Separate from the read router, and at its own prefix, because everyone
/// reads and only an administrator writes: a rate is a property of the
/// deployment, and `is_admin` is the role that owns deployment-wide decisions
/// (see docs/server/auth.md). Sharing the `/rates` prefix would put the admin
/// gate in front of every read -- mount middleware runs before the nested
/// router looks at the path.
Router buildRatesAdminRouter(Database db) {
  final router = Router();

  router.put('/<currency>', (Request request, String currency) async {
    final key = currency.trim().toLowerCase();
    if (key.isEmpty) return Response(400, body: 'invalid currency');
    final dynamic body;
    try {
      body = jsonDecode(await request.readAsString());
    } catch (_) {
      return Response(400, body: 'invalid JSON');
    }
    if (body is! Map) return Response(400, body: 'invalid JSON');
    final rate = body['rate'];
    // Zero and negatives are rejected rather than stored: the conversion maths
    // divides by a rate, so either one turns every converted figure into
    // infinity or a sign flip across the whole household at once.
    if (rate is! num || !rate.isFinite || rate <= 0) {
      return Response(400, body: 'rate must be a positive number');
    }
    db.execute(
      'INSERT INTO exchange_rate_overrides (currency, rate, updated_at) VALUES (?, ?, ?) '
      'ON CONFLICT(currency) DO UPDATE SET rate = excluded.rate, updated_at = excluded.updated_at',
      [key, rate.toDouble(), DateTime.now().millisecondsSinceEpoch],
    );
    return Response.ok(
      jsonEncode({'currency': key, 'rate': rate.toDouble()}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.delete('/<currency>', (Request request, String currency) {
    db.execute('DELETE FROM exchange_rate_overrides WHERE currency = ?',
        [currency.trim().toLowerCase()]);
    return Response.ok('');
  });

  return router;
}
