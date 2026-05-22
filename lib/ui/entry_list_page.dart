import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/entry_editor_page.dart';
import 'package:equation_solver_app/ui/solve_page.dart';
import 'package:equation_solver_app/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
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
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return ListTile(
                leading: const Icon(Icons.functions),
                title: Text(entry.name),
                subtitle: entry.description == null
                    ? null
                    : Text(
                        entry.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  onSelected: (action) async {
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
                    } else if (action == 'delete') {
                      await ref
                          .read(entriesRepoProvider)
                          .delete(entry.id);
                      refresh();
                    }
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SolvePage(
                      entryId: entry.id,
                      entryName: entry.name,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
