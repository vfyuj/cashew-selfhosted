import 'dart:io';

import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';

/// Operator rescue path for account provisioning.
///
/// Day-to-day, accounts are created from inside the app: the first person to
/// reach a fresh instance becomes its administrator via the setup wizard, and
/// that administrator adds everyone else. This CLI exists for the case that
/// flow can't recover from on its own -- a forgotten administrator password,
/// with no other administrator able to reset it.
///
/// Usage:
///   dart run bin/create_user.dart <email> [--name "Full Name"] [--admin]
///
/// Creates the account if the email is new, or issues a fresh temporary
/// password if it already exists. Either way it prints a password you can sign
/// in with immediately.
void main(List<String> args) {
  final positional = <String>[];
  var name = '';
  var forceAdmin = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--admin') {
      forceAdmin = true;
    } else if (arg == '--name') {
      if (i + 1 >= args.length) {
        stderr.writeln('--name requires a value');
        exit(1);
      }
      name = args[++i];
    } else if (arg.startsWith('--name=')) {
      name = arg.substring('--name='.length);
    } else if (arg.startsWith('-')) {
      stderr.writeln('Unknown option: $arg');
      exit(1);
    } else {
      positional.add(arg);
    }
  }

  if (positional.length != 1) {
    stderr.writeln('Usage: dart run bin/create_user.dart <email> [--name "Full Name"] [--admin]');
    exit(1);
  }
  final email = positional.single;
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';

  final db = openDatabase(dataDir);
  final authService = AuthService(db);
  final temporaryPassword = authService.generateTemporaryPassword();

  try {
    final existing = authService
        .listUsers()
        .where((u) => u.email.toLowerCase() == email.toLowerCase())
        .firstOrNull;

    if (existing != null) {
      // Re-running on an existing account rotates its password rather than
      // failing -- this is the whole point of the rescue path.
      authService.setPassword(existing.id, temporaryPassword);
      if (forceAdmin && !existing.isAdmin) {
        authService.setAdmin(existing.id, true);
      }
      print('Password reset for existing user: $email');
      print('All of that account\'s devices have been signed out.');
    } else {
      // The very first account has to be an administrator, or no one could
      // ever administer the instance.
      final isFirstUser = authService.countUsers() == 0;
      authService.createUser(
        email,
        temporaryPassword,
        name: name,
        isAdmin: forceAdmin || isFirstUser,
      );
      print('User created: $email${forceAdmin || isFirstUser ? ' (administrator)' : ''}');
    }
  } on WeakPasswordException {
    stderr.writeln('Generated password was rejected as too weak -- this is a bug.');
    db.dispose();
    exit(1);
  } catch (e) {
    stderr.writeln('Failed: $e');
    db.dispose();
    exit(1);
  }

  print('Temporary password: $temporaryPassword');
  print('Share this through a secure channel. Re-run this command at any time');
  print('to issue a new temporary password.');

  db.dispose();
}
