import 'package:cashew_selfhosted/database/tables.dart';

/// One row's worth of change, as the local merge understands it.
///
/// Upstream's model, kept deliberately: `processSyncLogs` in tables.dart
/// applies these under last-write-wins by `dateTimeModified`, and that merge is
/// tested and transport-agnostic. Only the transport around it was ever
/// replaced -- see `specs/00-overview.md`, principle 4.
///
/// It lives in a file of its own because both sides need it and neither can own
/// it: `tables.dart` consumes them, `liveSyncClient.dart` produces them, and
/// putting it in the producer would mean the database layer importing the sync
/// client. It used to sit in `syncClient.dart`, which was deleted when the
/// whole-database snapshot exchange was retired.
class SyncLog {
  SyncLog({
    this.deleteLogType,
    this.updateLogType,
    required this.transactionDateTime,
    required this.pk,
    this.itemToUpdate,
  });

  DeleteLogType? deleteLogType;
  UpdateLogType? updateLogType;
  DateTime? transactionDateTime;
  String pk;
  dynamic itemToUpdate;

  @override
  String toString() {
    return "SyncLog(deleteLogType: $deleteLogType, updateLogType: $updateLogType, transactionDateTime: $transactionDateTime, pk: $pk, itemToUpdate: $itemToUpdate)";
  }
}
