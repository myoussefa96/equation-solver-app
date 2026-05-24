import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/entry_list_page.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:equation_solver_app/ui/settings_page.dart';
import 'package:equation_solver_app/ui/widgets/text_field_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderListPage extends ConsumerStatefulWidget {
  const FolderListPage({super.key});

  @override
  ConsumerState<FolderListPage> createState() => _FolderListPageState();
}

class _FolderListPageState extends ConsumerState<FolderListPage> {
  final _selected = <int>{};
  bool get _selectMode => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersListProvider);
    return Scaffold(
      appBar: _selectMode ? _selectAppBar() : _normalAppBar(context),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createFolder(context),
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New group'),
            ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (folders) {
          if (folders.isEmpty) return _emptyState();
          return RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref.invalidate(foldersListProvider);
              await ref.read(foldersListProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _folderTile(folders[i]),
            ),
          );
        },
      ),
    );
  }

  AppBar _normalAppBar(BuildContext context) => AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      );

  AppBar _selectAppBar() => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
        ],
      );

  Widget _folderTile(FolderRow folder) {
    final selected = _selected.contains(folder.id);
    return Card(
      child: ListTile(
        selected: selected,
        leading: selected
            ? const Icon(Icons.check_circle)
            : const Icon(Icons.folder),
        title: Text(folder.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          setState(() => _selected.add(folder.id));
        },
        onTap: () {
          if (_selectMode) {
            setState(() {
              if (selected) {
                _selected.remove(folder.id);
              } else {
                _selected.add(folder.id);
              }
            });
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EntryListPage(folder: folder),
              ),
            );
          }
        },
        trailing: _selectMode
            ? null
            : PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (action) async {
                  if (action == 'rename') {
                    await _renameFolder(folder);
                  } else if (action == 'delete') {
                    await _deleteFolder(folder);
                  }
                },
              ),
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            Icon(
              Icons.folder_open,
              size: 96,
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No groups yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a group of formulas, or import the 15 formulas from your old app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New group'),
              onPressed: () => _createFolder(context),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Import from old app'),
              onPressed: () =>
                  runBundledImport(context, ref, replaceExisting: false),
            ),
          ],
        ),
      );

  Future<void> _createFolder(BuildContext context) async {
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

  Future<void> _renameFolder(FolderRow folder) async {
    final newName = await showTextFieldDialog(
      context,
      title: 'Rename group',
      initialValue: folder.name,
      confirmLabel: 'Rename',
    );
    if (newName != null) {
      await ref.read(foldersRepoProvider).rename(folder.id, newName);
      ref.invalidate(foldersListProvider);
    }
  }

  Future<void> _deleteFolder(FolderRow folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Text(
            'This will permanently delete "${folder.name}" and all its formulas.'),
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
      await ref.read(foldersRepoProvider).delete(folder.id);
      ref.invalidate(foldersListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${folder.name}"')),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Delete this group?' : 'Delete $count groups?'),
        content: Text(
          'This will permanently delete '
          '${count == 1 ? "the selected group" : "$count groups"} and all their formulas.',
        ),
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
      HapticFeedback.heavyImpact();
      final repo = ref.read(foldersRepoProvider);
      for (final id in _selected) {
        await repo.delete(id);
      }
      setState(_selected.clear);
      ref.invalidate(foldersListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Deleted $count ${count == 1 ? "group" : "groups"}')),
        );
      }
    }
  }
}
