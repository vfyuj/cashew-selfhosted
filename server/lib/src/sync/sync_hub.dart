import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory registry of open `/sync-stream` sockets per user, used to
/// deliver bare "something changed" wake-ups after a push. Deliberately
/// process-local: only correct because the server is a single Dart process
/// (see the documented constraint in specs/04-stage-2-instant-sync.md).
class SyncHub {
  final Map<int, Set<WebSocketChannel>> _sockets = {};

  void add(int userId, WebSocketChannel channel) {
    _sockets.putIfAbsent(userId, () => {}).add(channel);
  }

  void remove(int userId, WebSocketChannel channel) {
    final set = _sockets[userId];
    if (set == null) return;
    set.remove(channel);
    if (set.isEmpty) _sockets.remove(userId);
  }

  /// Notifies every open socket for this user. The notification carries no
  /// data -- the client's only reaction is to run an ordinary pull, so a
  /// dropped/duplicated/reordered message can never lose or double-apply data.
  void notify(int userId) {
    final set = _sockets[userId];
    if (set == null) return;
    final message = jsonEncode({'type': 'changed'});
    for (final channel in set) {
      try {
        channel.sink.add(message);
      } catch (_) {
        // Dead socket; onDone from its stream listener will remove it.
      }
    }
  }
}

/// Single process-wide instance, shared between the push handler
/// (sync_routes.dart) and the stream endpoint (sync_stream_routes.dart).
final syncHub = SyncHub();
