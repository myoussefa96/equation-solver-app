import 'package:equation_solver_app/engine/dependency_resolver.dart' show VarRole;
import 'package:equation_solver_app/storage/database.dart';

class VariableMetaDraft {
  const VariableMetaDraft({
    required this.entryId,
    required this.identifier,
    required this.displayLabel,
    this.unit,
    required this.role,
    this.isFinal = false,
    this.lastValue,
  });

  final int entryId;
  final String identifier;
  final String displayLabel;
  final String? unit;
  final VarRole role;
  final bool isFinal;
  final double? lastValue;
}

class VariableMetaRow {
  const VariableMetaRow({
    required this.id,
    required this.entryId,
    required this.identifier,
    required this.displayLabel,
    required this.unit,
    required this.role,
    required this.isFinal,
    required this.lastValue,
  });

  final int id;
  final int entryId;
  final String identifier;
  final String displayLabel;
  final String? unit;
  final VarRole role;
  final bool isFinal;
  final double? lastValue;
}

class VariableMetaRepo {
  const VariableMetaRepo(this._db);

  final AppDatabase _db;

  static String _roleText(VarRole r) => switch (r) {
        VarRole.input => 'input',
        VarRole.intermediate => 'intermediate',
        VarRole.output => 'output',
      };

  static VarRole _roleFromText(String s) => switch (s) {
        'input' => VarRole.input,
        'intermediate' => VarRole.intermediate,
        'output' => VarRole.output,
        _ => throw FormatException('Unknown role: $s'),
      };

  Future<int> put(VariableMetaDraft d) {
    return _db.raw.insert('variable_meta', {
      'entry_id': d.entryId,
      'identifier': d.identifier,
      'display_label': d.displayLabel,
      'unit': d.unit,
      'role': _roleText(d.role),
      'is_final': d.isFinal ? 1 : 0,
      'last_value': d.lastValue,
    });
  }

  Future<void> replaceAll(int entryId, List<VariableMetaDraft> drafts) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'variable_meta',
        where: 'entry_id = ?',
        whereArgs: [entryId],
      );
      for (final d in drafts) {
        await txn.insert('variable_meta', {
          'entry_id': d.entryId,
          'identifier': d.identifier,
          'display_label': d.displayLabel,
          'unit': d.unit,
          'role': _roleText(d.role),
          'is_final': d.isFinal ? 1 : 0,
          'last_value': d.lastValue,
        });
      }
    });
  }

  Future<void> updateLastValue(int entryId, String identifier, double value) {
    return _db.raw.update(
      'variable_meta',
      {'last_value': value},
      where: 'entry_id = ? AND identifier = ?',
      whereArgs: [entryId, identifier],
    );
  }

  Future<List<VariableMetaRow>> listByEntry(int entryId) async {
    final rows = await _db.raw.query(
      'variable_meta',
      where: 'entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (m) => VariableMetaRow(
            id: m['id']! as int,
            entryId: m['entry_id']! as int,
            identifier: m['identifier']! as String,
            displayLabel: m['display_label']! as String,
            unit: m['unit'] as String?,
            role: _roleFromText(m['role']! as String),
            isFinal: (m['is_final']! as int) != 0,
            lastValue: m['last_value'] as double?,
          ),
        )
        .toList();
  }
}
