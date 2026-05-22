import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

void main() {
  test('create + listByFolder returns the entry', () async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    final entries = EntriesRepo(db);
    final fId = await folders.create(name: 'f');
    final eId = await entries.create(
      folderId: fId,
      name: 'My formula',
      description: 'desc',
    );
    final list = await entries.listByFolder(fId);
    expect(list, hasLength(1));
    expect(list.first.id, equals(eId));
    expect(list.first.name, equals('My formula'));
    expect(list.first.description, equals('desc'));
    await db.close();
  });

  test('delete cascades from folder', () async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    final entries = EntriesRepo(db);
    final fId = await folders.create(name: 'f');
    await entries.create(folderId: fId, name: 'a');
    await folders.delete(fId);
    final remaining = await entries.listByFolder(fId);
    expect(remaining, isEmpty);
    await db.close();
  });

  test('rename + updateDescription persist', () async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    final entries = EntriesRepo(db);
    final fId = await folders.create(name: 'f');
    final id = await entries.create(folderId: fId, name: 'a');
    await entries.rename(id, 'b');
    await entries.updateDescription(id, 'new desc');
    final e = (await entries.listByFolder(fId)).first;
    expect(e.name, equals('b'));
    expect(e.description, equals('new desc'));
    await db.close();
  });
}
