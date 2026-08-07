import 'dart:io';
import 'dart:math';

import 'package:server/src/auth/auth_service.dart';
import 'package:server/src/database.dart';

/// Provisions a new user account. Run once per person by whoever operates
/// the server -- there is no public self-registration (see
/// specs/03-stage-1-kill-google.md).
///
/// Usage: dart run bin/create_user.dart <email>
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/create_user.dart <email>');
    exit(1);
  }
  final email = args[0];
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';

  final db = openDatabase(dataDir);
  final authService = AuthService(db);

  final tempPassword = _generateTempPassword();
  try {
    authService.createUser(email, tempPassword);
  } catch (e) {
    stderr.writeln('Failed to create user (maybe the email already exists?): $e');
    db.dispose();
    exit(1);
  }

  print('User created: $email');
  print('Temporary password: $tempPassword');
  print('Share this with the user through a secure channel. There is no password reset flow;');
  print('re-run this command to issue a new temporary password if needed.');

  db.dispose();
}

String _generateTempPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
}
