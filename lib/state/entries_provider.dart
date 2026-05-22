import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final entriesRepoProvider = Provider<EntriesRepo>(
  (ref) => EntriesRepo(ref.watch(dbProvider)),
);

final entriesByFolderProvider =
    FutureProvider.family<List<EntryRow>, int>(
  (ref, folderId) => ref.watch(entriesRepoProvider).listByFolder(folderId),
);
