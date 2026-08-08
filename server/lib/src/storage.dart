import 'dart:io';

import 'package:path/path.dart' as p;

class FileMetadata {
  final String filename;
  final DateTime modifiedTime;
  final int size;
  FileMetadata(this.filename, this.modifiedTime, this.size);

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'modifiedTime': modifiedTime.toUtc().toIso8601String(),
        'size': size,
      };
}

class InvalidFilenameException implements Exception {}

/// Per-user, per-namespace file storage (sync snapshots or backups),
/// replacing Google Drive's appDataFolder. Scoped by caller to the
/// authenticated user's own directory -- never a client-supplied path.
class UserFileStore {
  final String namespaceDir;
  UserFileStore(String dataDir, String namespace, int userId)
      : namespaceDir = p.join(dataDir, namespace, userId.toString());

  Directory _ensureDir() => Directory(namespaceDir)..createSync(recursive: true);

  /// Rejects path separators and traversal so a filename can never escape
  /// the user's own namespace directory.
  String _safePath(String filename) {
    if (filename.isEmpty || filename != p.basename(filename) || filename == '.' || filename == '..') {
      throw InvalidFilenameException();
    }
    return p.join(_ensureDir().path, filename);
  }

  List<FileMetadata> list() {
    final dir = _ensureDir();
    final entries = dir.listSync().whereType<File>();
    return entries.map((file) {
      final stat = file.statSync();
      return FileMetadata(p.basename(file.path), stat.modified, stat.size);
    }).toList();
  }

  void write(String filename, List<int> bytes) {
    File(_safePath(filename)).writeAsBytesSync(bytes);
  }

  List<int>? read(String filename) {
    final file = File(_safePath(filename));
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  bool delete(String filename) {
    final file = File(_safePath(filename));
    if (!file.existsSync()) return false;
    file.deleteSync();
    return true;
  }
}
