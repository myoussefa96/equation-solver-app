import 'dart:convert';

import 'package:equation_solver_app/engine/legacy_importer.dart';
import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/import_service.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> runBundledImport(
  BuildContext context,
  WidgetRef ref, {
  required bool replaceExisting,
}) async {
  final raw = await rootBundle.loadString('assets/migration_seed.json');
  final seed = jsonDecode(raw) as Map<String, Object?>;
  final report = LegacyImporter.importSeedWithReport(seed);

  final service = ImportService(
    folders: ref.read(foldersRepoProvider),
    entries: ref.read(entriesRepoProvider),
    equations: ref.read(equationsRepoProvider),
    variables: ref.read(variableMetaRepoProvider),
  );
  await service.importParsedFolders(
    report.folders,
    replaceExisting: replaceExisting,
  );

  ref.invalidate(foldersListProvider);

  if (context.mounted) {
    final folderCount = report.folders.length;
    final entryCount = report.folders.fold<int>(
      0,
      (n, f) => n + f.entries.length,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(
          'Imported $entryCount formulas in $folderCount groups.'
          '${report.skipped.isEmpty ? '' : "\n${report.skipped.length} formulas couldn't be imported."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Pure headless import — no UI, no providers. Returns the imported entry count.
/// Safe to call before runApp() during cold start.
Future<int> runBundledImportHeadless({
  required FoldersRepo folders,
  required EntriesRepo entries,
  required EquationsRepo equations,
  required VariableMetaRepo variables,
  required bool replaceExisting,
}) async {
  final raw = await rootBundle.loadString('assets/migration_seed.json');
  final seed = jsonDecode(raw) as Map<String, Object?>;
  final report = LegacyImporter.importSeedWithReport(seed);

  final service = ImportService(
    folders: folders,
    entries: entries,
    equations: equations,
    variables: variables,
  );
  await service.importParsedFolders(
    report.folders,
    replaceExisting: replaceExisting,
  );

  return report.folders.fold<int>(0, (n, f) => n + f.entries.length);
}
