import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final foldersRepoProvider = Provider<FoldersRepo>(
  (ref) => FoldersRepo(ref.watch(dbProvider)),
);

final foldersListProvider = FutureProvider<List<FolderRow>>(
  (ref) => ref.watch(foldersRepoProvider).listAll(),
);
