import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final equationsRepoProvider = Provider<EquationsRepo>(
  (ref) => EquationsRepo(ref.watch(dbProvider)),
);

final variableMetaRepoProvider = Provider<VariableMetaRepo>(
  (ref) => VariableMetaRepo(ref.watch(dbProvider)),
);

class EntryDetail {
  const EntryDetail({required this.equations, required this.variables});

  final List<EquationRow> equations;
  final List<VariableMetaRow> variables;
}

final entryDetailProvider =
    FutureProvider.family<EntryDetail, int>((ref, entryId) async {
  final eqs = await ref.watch(equationsRepoProvider).listByEntry(entryId);
  final vars =
      await ref.watch(variableMetaRepoProvider).listByEntry(entryId);
  return EntryDetail(equations: eqs, variables: vars);
});
