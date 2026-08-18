// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
//@dart=2.12
import 'package:drift/drift.dart';
import 'package:drift/internal/migrations.dart';
import 'schema_v33.dart' as v33;
import 'schema_v34.dart' as v34;
import 'schema_v35.dart' as v35;
import 'schema_v36.dart' as v36;
import 'schema_v37.dart' as v37;
import 'schema_v38.dart' as v38;
import 'schema_v39.dart' as v39;
import 'schema_v40.dart' as v40;
import 'schema_v41.dart' as v41;
import 'schema_v42.dart' as v42;
import 'schema_v43.dart' as v43;
import 'schema_v44.dart' as v44;
import 'schema_v45.dart' as v45;
import 'schema_v46.dart' as v46;
import 'schema_v47.dart' as v47;
import 'schema_v48.dart' as v48;

class GeneratedHelper implements SchemaInstantiationHelper {
  @override
  GeneratedDatabase databaseForVersion(QueryExecutor db, int version) {
    switch (version) {
      case 33:
        return v33.DatabaseAtV33(db);
      case 34:
        return v34.DatabaseAtV34(db);
      case 35:
        return v35.DatabaseAtV35(db);
      case 36:
        return v36.DatabaseAtV36(db);
      case 37:
        return v37.DatabaseAtV37(db);
      case 38:
        return v38.DatabaseAtV38(db);
      case 39:
        return v39.DatabaseAtV39(db);
      case 40:
        return v40.DatabaseAtV40(db);
      case 41:
        return v41.DatabaseAtV41(db);
      case 42:
        return v42.DatabaseAtV42(db);
      case 43:
        return v43.DatabaseAtV43(db);
      case 44:
        return v44.DatabaseAtV44(db);
      case 45:
        return v45.DatabaseAtV45(db);
      case 46:
        return v46.DatabaseAtV46(db);
      case 47:
        return v47.DatabaseAtV47(db);
      case 48:
        return v48.DatabaseAtV48(db);
      default:
        throw MissingSchemaException(version, const {
          33,
          34,
          35,
          36,
          37,
          38,
          39,
          40,
          41,
          42,
          43,
          44,
          45,
          46,
          47,
          48
        });
    }
  }
}
