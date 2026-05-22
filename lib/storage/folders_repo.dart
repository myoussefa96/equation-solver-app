import 'package:equation_solver_app/storage/database.dart';

class FolderRow {
  const FolderRow({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FolderRow.fromMap(Map<String, Object?> m) => FolderRow(
        id: m['id']! as int,
        name: m['name']! as String,
        sortOrder: m['sort_order']! as int,
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
      );

  final int id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FoldersRepo {
  const FoldersRepo(this._db);

  final AppDatabase _db;

  Future<int> create({required String name, int sortOrder = 0}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.raw.insert('folders', {
      'name': name,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> rename(int id, String newName) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.raw.update(
      'folders',
      {'name': newName, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) =>
      _db.raw.delete('folders', where: 'id = ?', whereArgs: [id]);

  Future<List<FolderRow>> listAll() async {
    final rows = await _db.raw.query('folders', orderBy: 'sort_order ASC, id ASC');
    return rows.map(FolderRow.fromMap).toList();
  }

  Future<FolderRow?> getById(int id) async {
    final rows = await _db.raw.query('folders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return FolderRow.fromMap(rows.first);
  }
}
