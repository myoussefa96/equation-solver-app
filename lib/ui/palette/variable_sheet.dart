import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:equation_solver_app/engine/slugify.dart';
import 'package:equation_solver_app/ui/editor/editor_state.dart';
import 'package:flutter/material.dart';

enum VariableSheetMode { insert, swap, output }

class VariableSheetResult {
  const VariableSheetResult.existing(this.identifier) : created = null;
  const VariableSheetResult.created(DraftVarMeta this.created)
      : identifier = '';

  String get effectiveIdentifier => created?.identifier ?? identifier;

  final String identifier;
  final DraftVarMeta? created;
}

class VariableEntry {
  const VariableEntry(this.identifier, this.label, this.unit, this.role);
  final String identifier;
  final String label;
  final String? unit;
  final VarRole role;
}

Future<VariableSheetResult?> showVariableSheet(
  BuildContext context, {
  required VariableSheetMode mode,
  required List<VariableEntry> existingVars,
  required Set<String> reservedIdentifiers,
}) {
  return showModalBottomSheet<VariableSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _VariableSheetBody(
      mode: mode,
      existingVars: existingVars,
      reservedIdentifiers: reservedIdentifiers,
    ),
  );
}

class _VariableSheetBody extends StatelessWidget {
  const _VariableSheetBody({
    required this.mode,
    required this.existingVars,
    required this.reservedIdentifiers,
  });

  final VariableSheetMode mode;
  final List<VariableEntry> existingVars;
  final Set<String> reservedIdentifiers;

  @override
  Widget build(BuildContext context) {
    final inputs = existingVars.where((v) => v.role == VarRole.input).toList();
    final outputs =
        existingVars.where((v) => v.role == VarRole.output).toList();
    final constants = OpRegistry.constants.keys.toList();

    final title = mode == VariableSheetMode.output
        ? 'What does this formula compute?'
        : (mode == VariableSheetMode.swap
            ? 'Swap variable'
            : 'Pick a variable');

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                if (mode != VariableSheetMode.output) ...[
                  _section(ctx, 'You enter'),
                  if (inputs.isEmpty)
                    _placeholder(ctx, '(none yet — create one)')
                  else
                    for (final v in inputs)
                      _row(
                          ctx,
                          v,
                          () => Navigator.of(ctx)
                              .pop(VariableSheetResult.existing(v.identifier))),
                  _section(ctx, 'Computed from earlier formulas'),
                  if (outputs.isEmpty)
                    _placeholder(
                        ctx, '(none yet — earlier formulas will appear here)')
                  else
                    for (final v in outputs)
                      _row(
                          ctx,
                          v,
                          () => Navigator.of(ctx)
                              .pop(VariableSheetResult.existing(v.identifier))),
                  _section(ctx, 'Constants'),
                  for (final name in constants)
                    ListTile(
                      title: Text(name,
                          style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(OpRegistry.constants[name]!.toString()),
                      onTap: () => Navigator.of(ctx)
                          .pop(VariableSheetResult.existing(name)),
                    ),
                ] else ...[
                  _section(
                      ctx, 'Pick a variable already used in this entry'),
                  if (outputs.isEmpty)
                    _placeholder(ctx, '(no orphan variables)')
                  else
                    for (final v in outputs)
                      _row(
                          ctx,
                          v,
                          () => Navigator.of(ctx)
                              .pop(VariableSheetResult.existing(v.identifier))),
                ],
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(mode == VariableSheetMode.output
                        ? 'New computed variable…'
                        : 'New variable…'),
                    onPressed: () async {
                      final created = await _showCreateVariableForm(
                        ctx,
                        existingIdentifiers: {
                          ...existingVars.map((v) => v.identifier),
                          ...reservedIdentifiers,
                        },
                        forcedRole: mode == VariableSheetMode.output
                            ? VarRole.output
                            : null,
                      );
                      if (created != null && ctx.mounted) {
                        Navigator.of(ctx)
                            .pop(VariableSheetResult.created(created));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext ctx, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
      );

  Widget _placeholder(BuildContext ctx, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
      );

  Widget _row(BuildContext ctx, VariableEntry v, VoidCallback onTap) {
    final scheme = Theme.of(ctx).colorScheme;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: v.role == VarRole.input
                  ? scheme.tertiaryContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(v.identifier,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v.label)),
          if (v.unit != null)
            Text('[${v.unit}]', style: TextStyle(color: scheme.outline)),
        ],
      ),
    );
  }
}

Future<DraftVarMeta?> _showCreateVariableForm(
  BuildContext context, {
  required Set<String> existingIdentifiers,
  required VarRole? forcedRole,
}) async {
  final nameCtrl = TextEditingController();
  final unitCtrl = TextEditingController();
  VarRole? role = forcedRole;
  String? nameError;

  return showDialog<DraftVarMeta>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add a variable'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Pm or rho',
                  errorText: nameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "We'll use this name everywhere you see it.",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  hintText: 'e.g. kg/m³',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Role',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<VarRole>(
                title: const Text("I'll type this in"),
                subtitle: const Text('(like Pm, Pe, K…)'),
                value: VarRole.input,
                groupValue: role,
                onChanged: forcedRole != null
                    ? null
                    : (v) => setState(() => role = v),
              ),
              RadioListTile<VarRole>(
                title:
                    const Text('The app calculates it from another formula'),
                value: VarRole.output,
                groupValue: role,
                onChanged: forcedRole != null
                    ? null
                    : (v) => setState(() => role = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: role == null
                ? null
                : () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setState(() => nameError = 'Required');
                      return;
                    }
                    final identifier = slugify(name);
                    if (OpRegistry.isReservedIdentifier(identifier)) {
                      setState(() => nameError =
                          'This name is reserved — try a different one.');
                      return;
                    }
                    if (existingIdentifiers.contains(identifier)) {
                      setState(() => nameError =
                          'Already used by another variable — pick a different name.');
                      return;
                    }
                    Navigator.of(ctx).pop(DraftVarMeta(
                      identifier: identifier,
                      displayLabel: name,
                      unit: unitCtrl.text.trim().isEmpty
                          ? null
                          : unitCtrl.text.trim(),
                      role: role!,
                    ));
                  },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
