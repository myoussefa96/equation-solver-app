import 'package:equation_solver_app/engine/dependency_resolver.dart'
    show VarRole;
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

Future<int> _makeEntry(_TestCtx ctx) async {
  final fId = await ctx.folders.create(name: 'f');
  return ctx.entries.create(folderId: fId, name: 'e');
}

void main() {
  test('put + listByEntry returns rows with correct role + isFinal', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    await ctx.variables.put(VariableMetaDraft(
      entryId: entryId,
      identifier: 'Q',
      displayLabel: 'Flow rate',
      unit: 'm3/h',
      role: VarRole.input,
    ),);
    await ctx.variables.put(VariableMetaDraft(
      entryId: entryId,
      identifier: 'P',
      displayLabel: 'Pressure drop',
      unit: 'bar',
      role: VarRole.output,
      isFinal: true,
    ),);

    final rows = await ctx.variables.listByEntry(entryId);
    expect(rows, hasLength(2));

    final q = rows.firstWhere((r) => r.identifier == 'Q');
    expect(q.role, equals(VarRole.input));
    expect(q.isFinal, isFalse);
    expect(q.unit, equals('m3/h'));

    final p = rows.firstWhere((r) => r.identifier == 'P');
    expect(p.role, equals(VarRole.output));
    expect(p.isFinal, isTrue);

    await db.close();
  });

  test('replaceAll wipes existing rows and inserts new ones atomically',
      () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    await ctx.variables.put(VariableMetaDraft(
      entryId: entryId,
      identifier: 'A',
      displayLabel: 'Old A',
      role: VarRole.input,
    ),);
    await ctx.variables.put(VariableMetaDraft(
      entryId: entryId,
      identifier: 'B',
      displayLabel: 'Old B',
      role: VarRole.intermediate,
    ),);
    expect(await ctx.variables.listByEntry(entryId), hasLength(2));

    await ctx.variables.replaceAll(entryId, [
      VariableMetaDraft(
        entryId: entryId,
        identifier: 'C',
        displayLabel: 'New C',
        role: VarRole.output,
        isFinal: true,
      ),
    ]);

    final after = await ctx.variables.listByEntry(entryId);
    expect(after, hasLength(1));
    expect(after.first.identifier, equals('C'));
    expect(after.first.role, equals(VarRole.output));
    expect(after.first.isFinal, isTrue);

    await db.close();
  });

  test('updateLastValue persists the new value', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    await ctx.variables.put(VariableMetaDraft(
      entryId: entryId,
      identifier: 'T',
      displayLabel: 'Temperature',
      unit: 'C',
      role: VarRole.input,
    ),);

    await ctx.variables.updateLastValue(entryId, 'T', 250.5);

    final rows = await ctx.variables.listByEntry(entryId);
    expect(rows.first.lastValue, equals(250.5));

    await db.close();
  });

  test('CHECK constraint on role rejects invalid values', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    expect(
      () async => db.raw.insert('variable_meta', {
        'entry_id': entryId,
        'identifier': 'X',
        'display_label': 'Bad var',
        'role': 'bogus',
        'is_final': 0,
      }),
      throwsA(anything),
    );

    await db.close();
  });
}

class _TestCtx {
  _TestCtx(AppDatabase db)
      : folders = FoldersRepo(db),
        entries = EntriesRepo(db),
        variables = VariableMetaRepo(db);

  final FoldersRepo folders;
  final EntriesRepo entries;
  final VariableMetaRepo variables;
}
