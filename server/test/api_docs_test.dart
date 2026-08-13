import 'dart:io';

import 'package:test/test.dart';

/// Keeps `docs/server/api.md` honest.
///
/// That page exists so an agent (or an auditor) can learn the whole HTTP
/// surface from one file instead of reading `api.dart` plus six route files. A
/// stale reference is worse than none -- someone trusting it wastes more than
/// they saved -- so the route table is checked against the source in both
/// directions: every route the server serves must be documented, and every
/// documented route must still exist.
///
/// `shelf_router` exposes no public route table, so the routes are read out of
/// the source text. The mount prefixes below mirror `buildApiRouter` in
/// `lib/src/api.dart`; adding a new mounted router means adding a line here.
const _mountPrefixes = <String, String>{
  // Registered directly on the top-level router: /health and /sync-stream.
  'lib/src/api.dart': '',
  'lib/src/auth/auth_routes.dart': '/auth',
  'lib/src/sync/sync_routes.dart': '/sync',
  'lib/src/backup/backup_routes.dart': '/backup',
  'lib/src/attachments/attachment_routes.dart': '/attachments',
  'lib/src/admin/admin_routes.dart': '/admin',
};

final _routeCall = RegExp(r"""router\.(get|post|put|delete|patch)\(\s*'([^']*)'""");

/// Table rows only (`| `GET /health` | ... |`), so a path mentioned in the
/// prose around the table is not mistaken for a documented route.
final _documentedRow = RegExp(r"^\|\s*`([A-Z]+) (/[^`]*)`\s*\|", multiLine: true);

Set<String> _routesInSource() {
  final routes = <String>{};
  _mountPrefixes.forEach((path, prefix) {
    final source = File(path).readAsStringSync();
    for (final match in _routeCall.allMatches(source)) {
      final method = match.group(1)!.toUpperCase();
      final subPath = match.group(2)!;
      // A sub-router's '/' is the mount root itself.
      final full = subPath == '/' ? prefix : '$prefix$subPath';
      routes.add('$method $full');
    }
  });
  return routes;
}

void main() {
  test('docs/server/api.md documents exactly the routes the server serves', () {
    final doc = File('../docs/server/api.md').readAsStringSync();
    final documented = _documentedRow
        .allMatches(doc)
        .map((m) => '${m.group(1)} ${m.group(2)}')
        .toSet();
    final actual = _routesInSource();

    expect(actual, isNotEmpty, reason: 'no routes parsed -- has the route syntax changed?');

    expect(
      actual.difference(documented),
      isEmpty,
      reason: 'these routes exist in server/lib/src but are missing from '
          'docs/server/api.md -- add a table row for each',
    );
    expect(
      documented.difference(actual),
      isEmpty,
      reason: 'these routes are documented in docs/server/api.md but no longer '
          'exist in server/lib/src -- remove the stale rows',
    );
  });
}
