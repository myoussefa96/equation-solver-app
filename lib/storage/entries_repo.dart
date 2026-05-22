import 'package:equation_solver_app/storage/database.dart';

class EntryRow {
  const EntryRow({
    required this.id,
    required this.folderId,
    required this.name,
    required this.description,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EntryRow.fromMap(Map<String, Object?> m) => EntryRow(
        id: m['id']! as int,
        folderId: m['folder_id']! as int,
        name: m['name']! as String,
        description: m['description'] as String?,
        sortOrder: m['sort_order']! as int,
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
      );

  final int id;
  final int folderId;
  final String name;
  final String? description;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class EntriesRepo {
  const EntriesRepo(this._db);

  final AppDatabase _db;

  Future<int> create({
    required int folderId,
    required String name,
    String? description,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.raw.insert('entries', {
      'folder_id': folderId,
      'name': name,
      'description': description,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> rename(int id, String newName) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.raw.update(
      'entries',
      {'name': newName, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateDescription(int id, String? newDescription) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.raw.update(
      'entries',
      {'description': newDescription, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) =>
      _db.raw.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<List<EntryRow>> listByFolder(int folderId) async {
    final rows = await _db.raw.query(
      'entries',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(EntryRow.fromMap).toList();
  }

  Future<EntryRow?> getById(int id) async {
    final rows =
        await _db.raw.query('entries', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return EntryRow.fromMap(rows.first);
  }
}
