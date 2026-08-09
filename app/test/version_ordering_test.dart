import 'package:cashew_selfhosted/widgets/showChangelog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the ordering that decides whether the changelog popup appears.
///
/// `.githooks/pre-commit` bumps the version on every commit, so this comparison
/// runs on every launch, and getting it wrong is silent in both directions: too
/// permissive and the changelog reappears after every deploy, too strict and it
/// never appears at all. The previous implementation stripped the dots and
/// called `int.parse`, which throws on any pre-release suffix and returned 0 --
/// the "never appears" failure.
///
/// See specs/07-versioning.md.
void main() {
  int v(String s) => parseVersionInt(s);

  group('parseVersionInt', () {
    test('orders successive betas', () {
      expect(v('1.0.0-beta.1'), lessThan(v('1.0.0-beta.2')));
      expect(v('1.0.0-beta.9'), lessThan(v('1.0.0-beta.10')),
          reason: 'must compare numerically, not as text');
      expect(v('1.0.0-beta.99'), lessThan(v('1.0.0-beta.100')));
    });

    test('a release outranks every pre-release of the same version', () {
      expect(v('1.0.0-beta.1'), lessThan(v('1.0.0')));
      expect(v('1.0.0-beta.9999'), lessThan(v('1.0.0')));
      expect(v('1.0.0'), lessThan(v('1.0.1')));
    });

    test('orders major, minor and patch', () {
      expect(v('1.0.0'), lessThan(v('1.1.0')));
      expect(v('1.9.0'), lessThan(v('1.10.0')));
      expect(v('1.99.99'), lessThan(v('2.0.0')));
    });

    test('the abandoned upstream lineage still parses and outranks 1.x', () {
      // Not a bug -- it is why getChangelogPointsWidgets resets a stored
      // lastLoginVersion that is newer than the running version.
      expect(v(upstreamBaseVersion), greaterThan(v('1.0.0')));
    });

    test('unparseable input is version zero', () {
      expect(v(''), 0);
      expect(v('not a version'), 0);
      expect(v('5'), 0);
      expect(v('5.4'), 0);
    });

    test('equal versions compare equal', () {
      expect(v('1.0.0-beta.7'), v('1.0.0-beta.7'));
      expect(v('1.0.0-beta.7'), v(' 1.0.0-beta.7 '), reason: 'trimmed');
    });

    test('stays exact on the web, where ints are doubles', () {
      // Dart-on-web ints are JS numbers, exact only below 2^53.
      expect(v('9999.999.999'), lessThan(9007199254740991));
    });
  });

  group('changelog sections', () {
    test('every section heading parses to a real version', () {
      final headings = getChangelogString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('< '))
          .map((line) => line.replaceAll('< ', ''));

      expect(headings, isNotEmpty);
      for (final heading in headings) {
        expect(v(heading), greaterThan(0),
            reason: '"$heading" would be treated as version 0 and always show');
      }
    });
  });
}
