import 'dart:convert';

import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/ast_json.dart';
import 'package:equation_solver_app/storage/database.dart';

class EquationDraft {
  const EquationDraft({
    required this.entryId,
    required this.outputVar,
    required this.ast,
    required this.sortOrder,
  });

  final int entryId;
  final String outputVar;
  final AstNode ast;
  final int sortOrder;
}

class EquationRow {
  const EquationRow({
    required this.id,
    required this.entryId,
    required this.outputVar,
    required this.ast,
    required this.sortOrder,
  });

  final int id;
  final int entryId;
  final String outputVar;
  final AstNode ast;
  final int sortOrder;
}

class EquationsRepo {
  const EquationsRepo(this._db);

  final AppDatabase _db;

  Future<int> put(EquationDraft draft) async {
    return _db.raw.insert('equations', {
      'entry_id': draft.entryId,
      'output_var': draft.outputVar,
      'ast_json': jsonEncode(astToJson(draft.ast)),
      'sort_order': draft.sortOrder,
    });
  }

  /// Atomically replace all equations for an entry.
  Future<void> replaceAll(int entryId, List<EquationDraft> drafts) async {
    await _db.transaction((txn) async {
      await txn.delete('equations', where: 'entry_id = ?', whereArgs: [entryId]);
      for (final d in drafts) {
        await txn.insert('equations', {
          'entry_id': d.entryId,
          'output_var': d.outputVar,
          'ast_json': jsonEncode(astToJson(d.ast)),
          'sort_order': d.sortOrder,
        });
      }
    });
  }

  Future<List<EquationRow>> listByEntry(int entryId) async {
    final rows = await _db.raw.query(
      'equations',
      where: 'entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows
        .map(
          (m) => EquationRow(
            id: m['id']! as int,
            entryId: m['entry_id']! as int,
            outputVar: m['output_var']! as String,
            ast: astFromJson(
              jsonDecode(m['ast_json']! as String) as Map<String, Object?>,
            ),
            sortOrder: m['sort_order']! as int,
          ),
        )
        .toList();
  }

  Future<void> deleteById(int id) =>
      _db.raw.delete('equations', where: 'id = ?', whereArgs: [id]);
}
