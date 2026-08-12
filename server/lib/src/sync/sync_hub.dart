import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory registry of open `/sync-stream` sockets per dataset, used to
/// deliver bare "something changed" wake-ups after a push. Deliberately
/// process-local: only correct because the server is a single Dart process
/// (see the documented constraint in specs/04-stage-2-instant-sync.md).
class SyncHub {
  final Map<int, Set<WebSocketChannel>> _sockets = {};

  void add(int datasetId, WebSocketChannel channel) {
    _sockets.putIfAbsent(datasetId, () => {}).add(channel);
  }

  void remove(int datasetId, WebSocketChannel channel) {
    final set = _sockets[datasetId];
    if (set == null) return;
    set.remove(channel);
    if (set.isEmpty) _sockets.remove(datasetId);
  }

  /// Notifies every open socket for this dataset -- every device of every
  /// member of the household, not just the pusher's own. The notification carries no
  /// data -- the client's only reaction is to run an ordinary pull, so a
  /// dropped/duplicated/reordered message can never lose or double-apply data.
  void notify(int datasetId) {
    final set = _sockets[datasetId];
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
