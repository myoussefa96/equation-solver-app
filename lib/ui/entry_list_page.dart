import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/entries_repo.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/entry_editor_page.dart';
import 'package:equation_solver_app/ui/solve_page.dart';
import 'package:equation_solver_app/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntryListPage extends ConsumerWidget {
  const EntryListPage({super.key, required this.folder});
  final FolderRow folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesByFolderProvider(folder.id));
    void refresh() => ref.invalidate(entriesByFolderProvider(folder.id));

    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => EntryEditorPage(folderId: folder.id),
            ),
          );
          refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('New formula'),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.functions,
              title: 'No formulas in this group yet.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref.invalidate(entriesByFolderProvider(folder.id));
              await ref.read(entriesByFolderProvider(folder.id).future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) =>
                  _entryTile(context, ref, entries[i], refresh),
            ),
          );
        },
      ),
    );
  }

  Widget _entryTile(
    BuildContext context,
    WidgetRef ref,
    EntryRow entry,
    VoidCallback refresh,
  ) {
    final detailAsync = ref.watch(entryDetailProvider(entry.id));
    final preview = detailAsync.maybeWhen(
      data: (detail) => _formulaPreview(detail.equations),
      orElse: () => '',
    );

    return Card(
      child: ListTile(
        leading: const Icon(Icons.functions),
        title: Text(entry.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: preview.isEmpty
            ? (entry.description == null
                ? null
                : Text(entry.description!,
                    maxLines: 1, overflow: TextOverflow.ellipsis))
            : Text(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'solve', child: Text('Solve')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          onSelected: (action) =>
              _onAction(context, ref, entry, action, refresh),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SolvePage(entryId: entry.id, entryName: entry.name),
          ),
        ),
      ),
    );
  }

  String _formulaPreview(List<EquationRow> equations) {
    if (equations.isEmpty) return '';
    final lines = <String>[];
    for (final eq in equations.take(2)) {
      final rhs = _renderAst(eq.ast);
      final truncated = rhs.length > 35 ? '${rhs.substring(0, 32)}…' : rhs;
      lines.add('${eq.outputVar} = $truncated');
    }
    return lines.join('\n');
  }

  String _renderAst(AstNode n) {
    return switch (n) {
      NumberLit(:final value) => value.toString(),
      Identifier(:final name) => name,
      UnaryMinus(:final operand) => '-${_renderAst(operand)}',
      BinaryOp(:final op, :final left, :final right) =>
        '(${_renderAst(left)}$op${_renderAst(right)})',
      FunctionCall(:final name, :final args) =>
        '$name(${args.map(_renderAst).join(',')})',
    };
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    EntryRow entry,
    String action,
    VoidCallback refresh,
  ) async {
    if (action == 'edit') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EntryEditorPage(
            folderId: folder.id,
            entryId: entry.id,
          ),
        ),
      );
      refresh();
    } else if (action == 'solve') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SolvePage(entryId: entry.id, entryName: entry.name),
        ),
      );
    } else if (action == 'duplicate') {
      HapticFeedback.lightImpact();
      await _duplicate(ref, entry);
      refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated "${entry.name}"')),
        );
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this formula?'),
          content: Text('"${entry.name}" will be deleted permanently.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok ?? false) {
        HapticFeedback.mediumImpact();
        await ref.read(entriesRepoProvider).delete(entry.id);
        refresh();
      }
    }
  }

  Future<void> _duplicate(WidgetRef ref, EntryRow entry) async {
    final detail = await ref.read(entryDetailProvider(entry.id).future);
    final newEntryId = await ref.read(entriesRepoProvider).create(
          folderId: folder.id,
          name: '${entry.name} (copy)',
          description: entry.description,
        );
    await ref.read(equationsRepoProvider).replaceAll(
          newEntryId,
          [
            for (var i = 0; i < detail.equations.length; i++)
              EquationDraft(
                entryId: newEntryId,
                outputVar: detail.equations[i].outputVar,
                ast: detail.equations[i].ast,
                sortOrder: i,
              ),
          ],
        );
    await ref.read(variableMetaRepoProvider).replaceAll(
          newEntryId,
          [
            for (final v in detail.variables)
              VariableMetaDraft(
                entryId: newEntryId,
                identifier: v.identifier,
                displayLabel: v.displayLabel,
                unit: v.unit,
                role: v.role,
                isFinal: v.isFinal,
                lastValue: v.lastValue,
              ),
          ],
        );
  }
}
