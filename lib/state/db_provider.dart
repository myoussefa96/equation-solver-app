import 'package:equation_solver_app/storage/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in main() once the DB has been opened.
final dbProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('dbProvider must be overridden in main()');
});
