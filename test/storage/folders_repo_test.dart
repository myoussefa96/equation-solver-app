import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

void main() {
  test('create then list returns the folder', () async {
    final db = await openTestDb();
    final repo = FoldersRepo(db);

    final id = await repo.create(name: 'steam ejector sizing');
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.first.id, equals(id));
    expect(all.first.name, equals('steam ejector sizing'));
    await db.close();
  });

  test('rename updates name + updated_at', () async {
    final db = await openTestDb();
    final repo = FoldersRepo(db);
    final id = await repo.create(name: 'old');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.rename(id, 'new');
    final f = (await repo.listAll()).first;
    expect(f.name, equals('new'));
    expect(f.updatedAt.isAfter(f.createdAt), isTrue);
    await db.close();
  });

  test('delete removes the folder', () async {
    final db = await openTestDb();
    final repo = FoldersRepo(db);
    final id = await repo.create(name: 'a');
    await repo.delete(id);
    expect(await repo.listAll(), isEmpty);
    await db.close();
  });

  test('listAll orders by sort_order then id', () async {
    final db = await openTestDb();
    final repo = FoldersRepo(db);
    final a = await repo.create(name: 'a', sortOrder: 2);
    final b = await repo.create(name: 'b', sortOrder: 1);
    final ordered = await repo.listAll();
    expect(ordered.first.id, equals(b));
    expect(ordered.last.id, equals(a));
    await db.close();
  });
}
