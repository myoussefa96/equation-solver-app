import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/ui/entry_list_page.dart';
import 'package:equation_solver_app/ui/settings_page.dart';
import 'package:equation_solver_app/ui/widgets/empty_state.dart';
import 'package:equation_solver_app/ui/widgets/text_field_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderListPage extends ConsumerWidget {
  const FolderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createFolder(context, ref),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New group'),
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (folders) {
          if (folders.isEmpty) {
            return EmptyState(
              icon: Icons.folder_off_outlined,
              title:
                  'Start by creating a group of formulas,\nor import from your old app.',
              actionLabel: 'New group',
              onAction: () => _createFolder(context, ref),
            );
          }
          return ListView.separated(
            itemCount: folders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final folder = folders[i];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  onSelected: (action) async {
                    if (action == 'rename') {
                      final newName = await showTextFieldDialog(
                        context,
                        title: 'Rename group',
                        initialValue: folder.name,
                        confirmLabel: 'Rename',
                      );
                      if (newName != null) {
                        await ref
                            .read(foldersRepoProvider)
                            .rename(folder.id, newName);
                        ref.invalidate(foldersListProvider);
                      }
                    } else if (action == 'delete') {
                      final ok = await _confirmDelete(context, folder.name);
                      if (ok) {
                        await ref
                            .read(foldersRepoProvider)
                            .delete(folder.id);
                        ref.invalidate(foldersListProvider);
                      }
                    }
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntryListPage(folder: folder),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final name = await showTextFieldDialog(
      context,
      title: 'New group',
      hint: 'e.g. Pipe friction',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    await ref.read(foldersRepoProvider).create(name: name);
    ref.invalidate(foldersListProvider);
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Text(
            'This will permanently delete "$name" and all its formulas.',),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
