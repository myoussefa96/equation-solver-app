import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/state/folders_provider.dart';
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _section('Data'),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import from old app — add to library'),
            subtitle: const Text('15 formulas in 2 groups from the legacy Django app.'),
            onTap: () => runBundledImport(context, ref, replaceExisting: false),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Import from old app — replace library'),
            subtitle: const Text('Warning: this wipes everything you have first.'),
            onTap: () => _confirmReplaceImport(context, ref),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            title: const Text('Reset all data'),
            subtitle: const Text('Permanently deletes every group, formula, and value.'),
            onTap: () => _confirmEraseAll(context, ref),
          ),
          const Divider(height: 32),
          _section('Editor'),
          settingsAsync.when(
            loading: () => const ListTile(title: Text('Loading settings…')),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (settings) => SwitchListTile(
              secondary: const Icon(Icons.science),
              title: const Text('Advanced functions'),
              subtitle: const Text(
                'Show trigonometric inverse, hyperbolic, rounding, and other advanced functions in the keypad.',
              ),
              value: settings.advancedFunctionsEnabled,
              onChanged: (v) async {
                HapticFeedback.selectionClick();
                await ref
                    .read(appSettingsProvider.notifier)
                    .setAdvancedFunctionsEnabled(v);
              },
            ),
          ),
          const Divider(height: 32),
          _section('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Equation Solver'),
            subtitle: Text('Version 1.0'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Copy diagnostics'),
            subtitle: const Text('Useful when reporting a problem.'),
            onTap: () => _copyDiagnostics(context, ref),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Builder(
          builder: (context) => Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );

  Future<void> _confirmReplaceImport(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your library?'),
        content: const Text(
          'This deletes ALL your existing groups and formulas, then re-imports from the old app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok ?? false) {
      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      await runBundledImport(context, ref, replaceExisting: true);
    }
  }

  Future<void> _confirmEraseAll(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reset all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This permanently deletes everything in your library. Cannot be undone.'),
              const SizedBox(height: 12),
              const Text('Type ERASE to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: controller.text == 'ERASE' ? () => Navigator.of(ctx).pop(true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Erase'),
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) {
      if (!context.mounted) return;
      HapticFeedback.heavyImpact();
      final db = ref.read(dbProvider);
      // Folders cascade to entries, equations, variables.
      for (final f in await FoldersRepo(db).listAll()) {
        await FoldersRepo(db).delete(f.id);
      }
      ref.invalidate(foldersListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library reset.')),
        );
      }
    }
  }

  Future<void> _copyDiagnostics(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final folderCount = (await FoldersRepo(db).listAll()).length;
    final diag = '''
Equation Solver diagnostics
Version: 1.0
Schema: ${AppDatabase.schemaVersion}
Folders: $folderCount
''';
    await Clipboard.setData(ClipboardData(text: diag));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics copied to clipboard')),
      );
    }
  }
}
