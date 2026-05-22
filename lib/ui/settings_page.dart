import 'package:equation_solver_app/ui/import/import_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Data'),
            subtitle: Text('Import legacy formulas into your library.'),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import from old app — add to library'),
            subtitle: const Text(
                '15 formulas in 2 groups from the legacy Django app.',),
            onTap: () => runBundledImport(context, ref, replaceExisting: false),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Import from old app — replace library'),
            subtitle: const Text(
                'Warning: this wipes everything you have first.',),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Replace your library?'),
                  content: const Text(
                    'This deletes ALL your existing groups and formulas, '
                    'then re-imports from the old app.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Replace'),
                    ),
                  ],
                ),
              );
              if (ok ?? false) {
                if (!context.mounted) return;
                await runBundledImport(context, ref, replaceExisting: true);
              }
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('About'),
            subtitle: Text('Equation Solver v0.1'),
          ),
        ],
      ),
    );
  }
}
