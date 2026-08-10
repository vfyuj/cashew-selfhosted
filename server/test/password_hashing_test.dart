import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Password hashing runs on worker isolates behind a concurrency gate, so the
/// event loop never blocks on bcrypt and a burst of attempts can't turn into a
/// pile of live isolates. Both of those are easy to break silently, and the
/// gate hands slots between queued callers by hand -- exactly the kind of code
/// that deadlocks if it's wrong.
void main() {
  late Database db;
  late AuthService authService;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys=ON;');
    migrate(db);
    authService = AuthService(db);
  });

  tearDown(() => db.dispose());

  test('many concurrent logins all resolve correctly', () async {
    await authService.createUser('owner@example.com', 'correct-password');

    // Comfortably more than the gate's limit, so most of these have to queue
    // and be handed a slot by a finishing task rather than taking one.
    final attempts = <Future<bool>>[];
    for (var i = 0; i < 20; i++) {
      final rightPassword = i.isEven;
      attempts.add(
        authService
            .login('owner@example.com',
                rightPassword ? 'correct-password' : 'wrong-password')
            .then((_) => true)
            .catchError((Object e) {
          if (e is InvalidCredentialsException) return false;
          throw e;
        }),
      );
    }

    final results = await Future.wait(attempts).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw StateError('the hashing gate deadlocked'),
    );

    // Every even attempt used the right password, every odd one didn't --
    // no result got crossed with another's while they queued.
    for (var i = 0; i < results.length; i++) {
      expect(results[i], i.isEven, reason: 'attempt $i');
    }
  });

  test('the event loop keeps running while hashing is in flight', () async {
    // The whole point of the isolate: before it, a login froze every other
    // request on this single-threaded server for the duration.
    var ticks = 0;
    final ticker = Stream.periodic(const Duration(milliseconds: 5))
        .listen((_) => ticks++);

    await Future.wait([
      for (var i = 0; i < 4; i++) authService.hashPassword('some-password-$i'),
    ]);
    await ticker.cancel();

    expect(ticks, greaterThan(0),
        reason: 'the event loop was blocked for the whole hashing run');
  });

  test('a queued caller still gets its slot when an earlier one throws',
      () async {
    // A task that throws must hand its slot on in `finally`, or the gate
    // leaks capacity until nothing can run at all.
    await authService.createUser('owner@example.com', 'correct-password');

    final failures = [
      for (var i = 0; i < 8; i++)
        authService
            .login('nobody@example.com', 'whatever')
            .then<void>((_) {})
            .catchError((Object _) {})
    ];
    await Future.wait(failures);

    // If slots leaked, this never completes.
    final (session, user) =
        await authService.login('owner@example.com', 'correct-password').timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw StateError('the hashing gate leaked slots'),
            );
    expect(user.email, 'owner@example.com');
    expect(session.token, isNotEmpty);
  });
}
