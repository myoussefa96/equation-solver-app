import 'package:equation_solver_app/engine/parsed_entry.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';

class ImportService {
  const ImportService({
    required this.folders,
    required this.entries,
    required this.equations,
    required this.variables,
  });

  final FoldersRepo folders;
  final EntriesRepo entries;
  final EquationsRepo equations;
  final VariableMetaRepo variables;

  /// Write the imported folders into the DB. Each folder is created with the
  /// provided name; collisions are handled by appending " (imported)" if
  /// [replaceExisting] is false. If [replaceExisting] is true, ALL existing
  /// folders are deleted first (which cascades through entries / equations /
  /// variable_meta).
  Future<void> importParsedFolders(
    List<ParsedFolder> source, {
    bool replaceExisting = false,
  }) async {
    if (replaceExisting) {
      for (final f in await folders.listAll()) {
        await folders.delete(f.id);
      }
    }

    final existingNames =
        (await folders.listAll()).map((f) => f.name).toSet();

    for (var i = 0; i < source.length; i++) {
      final pf = source[i];
      var name = pf.name;
      while (existingNames.contains(name)) {
        name = '${pf.name} (imported)';
        if (existingNames.contains(name)) {
          // append index suffix to avoid infinite loop
          name = '${pf.name} (imported ${DateTime.now().microsecondsSinceEpoch})';
        }
      }
      existingNames.add(name);
      final folderId = await folders.create(name: name, sortOrder: i);

      for (var j = 0; j < pf.entries.length; j++) {
        final pe = pf.entries[j];
        final entryId = await entries.create(
          folderId: folderId,
          name: pe.name,
          description: pe.description,
          sortOrder: j,
        );

        await equations.replaceAll(entryId, [
          for (var k = 0; k < pe.equations.length; k++)
            EquationDraft(
              entryId: entryId,
              outputVar: pe.equations[k].outputVar,
              ast: pe.equations[k].ast,
              sortOrder: k,
            ),
        ]);

        await variables.replaceAll(entryId, [
          for (final v in pe.variables)
            VariableMetaDraft(
              entryId: entryId,
              identifier: v.identifier,
              displayLabel: v.displayLabel,
              unit: v.unit,
              role: v.role,
              isFinal: v.isFinal,
            ),
        ]);
      }
    }
  }
}
