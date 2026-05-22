import 'dart:convert';
import 'dart:io';
import 'package:equation_solver_app/engine/legacy_importer.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/import_service.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

void main() {
  test('imports the full seed (2 folders, 15 entries)', () async {
    final raw = File('assets/migration_seed.json').readAsStringSync();
    final seed = jsonDecode(raw) as Map<String, Object?>;
    final imported = LegacyImporter.importSeed(seed);

    final db = await openTestDb();
    final service = ImportService(
      folders: FoldersRepo(db),
      entries: EntriesRepo(db),
      equations: EquationsRepo(db),
      variables: VariableMetaRepo(db),
    );

    await service.importParsedFolders(imported);

    final foldersList = await FoldersRepo(db).listAll();
    expect(foldersList, hasLength(2));

    final entries = EntriesRepo(db);
    final allEntries = <int>[];
    for (final f in foldersList) {
      allEntries.addAll((await entries.listByFolder(f.id)).map((e) => e.id));
    }
    expect(allEntries, hasLength(15));

    // pick one and verify it round-trips
    final firstEntry = (await entries.listByFolder(foldersList.first.id)).first;
    final equations = EquationsRepo(db);
    final eqs = await equations.listByEntry(firstEntry.id);
    expect(eqs, isNotEmpty);
    await db.close();
  });

  test('replace mode wipes existing data first', () async {
    final db = await openTestDb();
    final folders = FoldersRepo(db);
    await folders.create(name: 'existing');

    final raw = File('assets/migration_seed.json').readAsStringSync();
    final seed = jsonDecode(raw) as Map<String, Object?>;
    final imported = LegacyImporter.importSeed(seed);

    final service = ImportService(
      folders: folders,
      entries: EntriesRepo(db),
      equations: EquationsRepo(db),
      variables: VariableMetaRepo(db),
    );
    await service.importParsedFolders(imported, replaceExisting: true);

    final all = await folders.listAll();
    // 2 imported, the 'existing' wiped
    expect(all, hasLength(2));
    expect(all.where((f) => f.name == 'existing'), isEmpty);
    await db.close();
  });
}
