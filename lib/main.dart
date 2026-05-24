import 'dart:io';

import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/app.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.openApp();

  // Auto-import bundled formulas on first launch when DB is empty.
  try {
    final folders = FoldersRepo(db);
    final existing = await folders.listAll();
    if (existing.isEmpty) {
      await runBundledImportHeadless(
        folders: folders,
        entries: EntriesRepo(db),
        equations: EquationsRepo(db),
        variables: VariableMetaRepo(db),
        replaceExisting: false,
      );
    }
  } catch (e, st) {
    stderr.writeln('[auto-import] failed, continuing with empty state: $e\n$st');
  }

  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const EquationSolverApp(),
    ),
  );
}
