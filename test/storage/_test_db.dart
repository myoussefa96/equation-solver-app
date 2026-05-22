import 'package:equation_solver_app/storage/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Returns an open in-memory database with the latest schema applied.
/// Each call returns a fresh DB — tests don't share state.
Future<AppDatabase> openTestDb() async {
  sqfliteFfiInit();
  return AppDatabase.openInMemory(databaseFactory: databaseFactoryFfi);
}
