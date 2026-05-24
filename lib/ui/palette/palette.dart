import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'function_picker_sheet.dart';

class Palette extends ConsumerStatefulWidget {
  const Palette({
    super.key,
    required this.activeRowLabel,
    required this.isOperatorContext,
    required this.existingVarChips,
    required this.onAppendDigit,
    required this.onToggleSign,
    required this.onScientificE,
    required this.onOpenGroup,
    required this.onCloseGroup,
    required this.onBackspace,
    required this.onNewVariable,
    required this.onInsertVarChip,
    required this.onOperator,
    required this.onFunctionPicked,
  });

  final String activeRowLabel;
  final bool isOperatorContext;
  final List<({String identifier, bool isInput})> existingVarChips;

  final void Function(String) onAppendDigit;
  final VoidCallback onToggleSign;
  final VoidCallback onScientificE;
  final VoidCallback onOpenGroup;
  final VoidCallback onCloseGroup;
  final VoidCallback onBackspace;

  final VoidCallback onNewVariable;
  final void Function(String identifier) onInsertVarChip;

  final void Function(String op) onOperator;
  final void Function(FunctionPick) onFunctionPicked;

  @override
  ConsumerState<Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<Palette>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _labels = ['123', 'Vars', '±×÷', 'fn'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _labels.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context),
          TabBar(
            controller: _tab,
            tabs: [for (final l in _labels) Tab(text: l)],
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: _tab,
              children: [
                _numbersTab(),
                _varsTab(),
                _operatorsTab(),
                _functionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.edit, size: 14, color: scheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Editing: ${widget.activeRowLabel}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.backspace_outlined),
            iconSize: 20,
            onPressed: widget.onBackspace,
            tooltip: 'Backspace',
          ),
        ],
      ),
    );
  }

  Widget _numbersTab() {
    final buttons = <(String, VoidCallback)>[
      ('7', () => widget.onAppendDigit('7')),
      ('8', () => widget.onAppendDigit('8')),
      ('9', () => widget.onAppendDigit('9')),
      ('.', () => widget.onAppendDigit('.')),
      ('4', () => widget.onAppendDigit('4')),
      ('5', () => widget.onAppendDigit('5')),
      ('6', () => widget.onAppendDigit('6')),
      ('±', widget.onToggleSign),
      ('1', () => widget.onAppendDigit('1')),
      ('2', () => widget.onAppendDigit('2')),
      ('3', () => widget.onAppendDigit('3')),
      ('(', widget.onOpenGroup),
      ('0', () => widget.onAppendDigit('0')),
      ('⌫', widget.onBackspace),
      ('EE', widget.onScientificE),
      (')', widget.onCloseGroup),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [for (final (l, f) in buttons) _PadKey(label: l, onTap: f)],
    );
  }

  Widget _varsTab() {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New variable'),
            onPressed: widget.onNewVariable,
          ),
          for (final v in widget.existingVarChips)
            ActionChip(
              backgroundColor: v.isInput
                  ? scheme.tertiaryContainer
                  : scheme.secondaryContainer,
              label: Text(v.identifier,
                  style: const TextStyle(fontFamily: 'monospace')),
              onPressed: () => widget.onInsertVarChip(v.identifier),
            ),
        ],
      ),
    );
  }

  Widget _operatorsTab() {
    final ops = <(String, String)>[
      ('+', '+'),
      ('−', '-'),
      ('×', '*'),
      ('÷', '/'),
      ('^', '^'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final (display, value) in ops)
            _PadKey(
              label: display,
              onTap: () => widget.onOperator(value),
              glow: widget.isOperatorContext,
              fg: scheme.primary,
            ),
          _PadKey(
              label: '(',
              onTap: widget.onOpenGroup,
              glow: !widget.isOperatorContext),
          _PadKey(label: ')', onTap: widget.onCloseGroup),
        ],
      ),
    );
  }

  Widget _functionsTab() {
    final advancedAsync = ref.watch(advancedFunctionsEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    return advancedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (advanced) {
        final entries = OpRegistry.functions.entries
            .where((e) => advanced || e.value.category == OpCategory.basic)
            .toList();
        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      advanced
                          ? 'Advanced functions on'
                          : 'Advanced functions off',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search all functions',
                    onPressed: () async {
                      final pick = await showFunctionPickerSheet(
                        context,
                        advancedEnabled: advanced,
                      );
                      if (pick != null) widget.onFunctionPicked(pick);
                    },
                  ),
                  Switch(
                    value: advanced,
                    onChanged: (v) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setAdvancedFunctionsEnabled(v);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.all(6),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final e in entries)
                    Material(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      elevation: 1,
                      child: InkWell(
                        onTap: () => widget.onFunctionPicked(
                            FunctionPick(e.key, e.value.arity)),
                        borderRadius: BorderRadius.circular(8),
                        child: Center(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.onTap,
    this.glow = false,
    this.fg,
  });

  final String label;
  final VoidCallback onTap;
  final bool glow;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: glow ? scheme.primaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: glow
                  ? scheme.onPrimaryContainer
                  : (fg ?? scheme.onSurface),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
