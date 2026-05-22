import 'package:equation_solver_app/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

void main() {
  test('opens a fresh in-memory DB with schema applied', () async {
    final db = await openTestDb();
    final tables = await db.raw
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((r) => r['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>{
        'folders',
        'entries',
        'equations',
        'variable_meta',
        'solve_history',
      }),
    );
    await db.close();
  });

  test('schema version matches expected', () async {
    final db = await openTestDb();
    final v = await db.raw.rawQuery('PRAGMA user_version');
    expect(v.first['user_version'], equals(AppDatabase.schemaVersion));
    await db.close();
  });

  test('foreign keys are enforced', () async {
    final db = await openTestDb();
    final r = await db.raw.rawQuery('PRAGMA foreign_keys');
    expect(r.first['foreign_keys'], equals(1));
    await db.close();
  });
}
