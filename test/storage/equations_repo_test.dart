import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import '_test_db.dart';

Future<int> _makeEntry(_TestCtx ctx) async {
  final fId = await ctx.folders.create(name: 'f');
  return ctx.entries.create(folderId: fId, name: 'e');
}

void main() {
  test('put + listByEntry round-trips AST', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    const ast = BinaryOp('+', Identifier('a'), NumberLit(2));
    await ctx.equations.put(EquationDraft(
      entryId: entryId,
      outputVar: 'r',
      ast: ast,
      sortOrder: 0,
    ),);

    final all = await ctx.equations.listByEntry(entryId);
    expect(all, hasLength(1));
    expect(all.first.outputVar, equals('r'));
    expect(all.first.ast, equals(ast));
    await db.close();
  });

  test('replaceAll deletes old rows and inserts new ones atomically', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);

    await ctx.equations.put(EquationDraft(
      entryId: entryId,
      outputVar: 'a',
      ast: const NumberLit(1),
      sortOrder: 0,
    ),);
    await ctx.equations.put(EquationDraft(
      entryId: entryId,
      outputVar: 'b',
      ast: const NumberLit(2),
      sortOrder: 1,
    ),);
    expect(await ctx.equations.listByEntry(entryId), hasLength(2));

    await ctx.equations.replaceAll(entryId, [
      EquationDraft(
        entryId: entryId,
        outputVar: 'c',
        ast: const NumberLit(3),
        sortOrder: 0,
      ),
    ]);
    final after = await ctx.equations.listByEntry(entryId);
    expect(after, hasLength(1));
    expect(after.first.outputVar, equals('c'));
    await db.close();
  });

  test('delete cascades from entries', () async {
    final db = await openTestDb();
    final ctx = _TestCtx(db);
    final entryId = await _makeEntry(ctx);
    await ctx.equations.put(EquationDraft(
      entryId: entryId,
      outputVar: 'r',
      ast: const NumberLit(1),
      sortOrder: 0,
    ),);
    await ctx.entries.delete(entryId);
    expect(await ctx.equations.listByEntry(entryId), isEmpty);
    await db.close();
  });
}

class _TestCtx {
  _TestCtx(AppDatabase db)
      : folders = FoldersRepo(db),
        entries = EntriesRepo(db),
        equations = EquationsRepo(db);

  final FoldersRepo folders;
  final EntriesRepo entries;
  final EquationsRepo equations;
}
