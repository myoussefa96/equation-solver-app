import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:equation_solver_app/ui/editor/chip_renderer.dart';
import 'package:equation_solver_app/ui/editor/editor_state.dart';
import 'package:equation_solver_app/ui/palette/function_picker_sheet.dart';
import 'package:equation_solver_app/ui/palette/number_sheet.dart';
import 'package:equation_solver_app/ui/palette/op_swap_popover.dart';
import 'package:equation_solver_app/ui/palette/palette.dart';
import 'package:equation_solver_app/ui/palette/variable_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntryEditorPage extends ConsumerStatefulWidget {
  const EntryEditorPage({
    super.key,
    this.entryId,
    required this.folderId,
  });

  final int? entryId;
  final int folderId;

  @override
  ConsumerState<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends ConsumerState<EntryEditorPage> {
  EditorState? _state;
  bool _loading = true;
  bool _saving = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _state?.removeListener(_onStateChange);
    _state?.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onStateChange() => setState(() {});

  Future<void> _load() async {
    if (widget.entryId == null) {
      _state = EditorState(
        entryId: null,
        folderId: widget.folderId,
        entryName: 'New formula',
      );
      _nameCtrl.text = _state!.name;
      _state!.addListener(_onStateChange);
      setState(() => _loading = false);
      return;
    }
    final entries = ref.read(entriesRepoProvider);
    final entry = await entries.getById(widget.entryId!);
    if (entry == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final detail =
        await ref.read(entryDetailProvider(widget.entryId!).future);
    final rows = <EditorRow>[];
    final outputByIdentifier = {
      for (final v in detail.variables) v.identifier: v,
    };
    for (final eq in detail.equations) {
      final chips = chipsFromAst(eq.ast);
      rows.add(EditorRow(
        output: VarChip(eq.outputVar),
        chips: chips,
      ));
      outputByIdentifier[eq.outputVar];
    }
    if (rows.isEmpty) rows.add(EditorRow());
    _state = EditorState(
      entryId: widget.entryId,
      folderId: widget.folderId,
      entryName: entry.name,
      entryDescription: entry.description,
      initialRows: rows,
    );
    _nameCtrl.text = entry.name;
    _state!.addListener(_onStateChange);
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = _state;
    if (s == null) return;
    setState(() => _saving = true);
    s.bannerError = null;

    if (s.name.trim().isEmpty) {
      setState(() {
        s.bannerError = 'Give this formula set a name.';
        _saving = false;
      });
      return;
    }

    final eqEntries = <EqEntry>[];
    final outputLabels = <String, String>{};
    for (var i = 0; i < s.rows.length; i++) {
      final r = s.rows[i];
      if (r.output == null && r.chips.isEmpty) continue;
      if (r.output == null) {
        r.rowError = 'Output variable is required.';
        setState(() {
          s.bannerError =
              'Formula ${i + 1}: tap the leftmost slot to pick an output variable.';
          _saving = false;
        });
        return;
      }
      if (r.chips.isEmpty) {
        r.rowError = 'Formula expression is required.';
        setState(() {
          s.bannerError = 'Formula ${i + 1}: build an expression using the keypad below.';
          _saving = false;
        });
        return;
      }
      final expr = flatten(r.chips);
      try {
        final ast = Parser(expr).parseExpression();
        eqEntries.add(EqEntry(output: r.output!.name, ast: ast));
        outputLabels[r.output!.name] =
            s.draftVarMeta[r.output!.name]?.displayLabel ?? r.output!.name;
      } on FormatException catch (e) {
        r.rowError = e.message;
        setState(() {
          s.bannerError = 'Formula ${i + 1}: ${e.message}';
          _saving = false;
        });
        return;
      }
    }
    if (eqEntries.isEmpty) {
      setState(() {
        s.bannerError = 'Add at least one formula.';
        _saving = false;
      });
      return;
    }
    ResolveResult resolved;
    try {
      resolved = DependencyResolver.resolve(eqEntries);
    } on EngineError catch (e) {
      setState(() {
        s.bannerError = e.userMessage;
        _saving = false;
      });
      return;
    }

    final entries = ref.read(entriesRepoProvider);
    int entryId;
    if (s.entryId == null) {
      entryId = await entries.create(
        folderId: s.folderId,
        name: s.name.trim(),
        description: s.description?.trim().isEmpty == true
            ? null
            : s.description?.trim(),
      );
    } else {
      entryId = s.entryId!;
      await entries.rename(entryId, s.name.trim());
    }

    final equationsRepo = ref.read(equationsRepoProvider);
    await equationsRepo.replaceAll(entryId, [
      for (var i = 0; i < eqEntries.length; i++)
        EquationDraft(
          entryId: entryId,
          outputVar: eqEntries[i].output,
          ast: eqEntries[i].ast,
          sortOrder: i,
        ),
    ]);

    final variablesRepo = ref.read(variableMetaRepoProvider);
    final variables = <VariableMetaDraft>[];
    for (final entryV in resolved.roles.entries) {
      final id = entryV.key;
      final role = entryV.value;
      final draft = s.draftVarMeta[id];
      variables.add(VariableMetaDraft(
        entryId: entryId,
        identifier: id,
        displayLabel: draft?.displayLabel ?? outputLabels[id] ?? id,
        unit: draft?.unit,
        role: role,
        isFinal: role == VarRole.output,
      ));
    }
    await variablesRepo.replaceAll(entryId, variables);

    ref.invalidate(entriesByFolderProvider(s.folderId));
    if (s.entryId != null) {
      ref.invalidate(entryDetailProvider(s.entryId!));
    }
    HapticFeedback.lightImpact();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Chip tap dispatchers
  // ---------------------------------------------------------------------------

  Future<void> _onChipTap(
      List<ChipNode> parent, int index, ChipNode chip) async {
    final s = _state!;
    s.setCaret(parent, index + 1);
    switch (chip) {
      case NumberChip(:final text):
        final newText = await showNumberSheet(context, initial: text);
        if (newText == null || newText.isEmpty) return;
        s.replaceChip(parent, index, NumberChip(newText));
      case VarChip(:final name):
        await _openVariableSheet(
          mode: VariableSheetMode.swap,
          onPick: (id) => s.replaceChip(parent, index, VarChip(id)),
          currentIdentifier: name,
        );
      case ConstChip():
        // No-op for now; tapping a constant could swap π <-> e.
        break;
      case OpChip(:final op):
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (overlay == null) return;
        final position = RelativeRect.fromRect(
          Rect.fromPoints(
            box.localToGlobal(Offset.zero, ancestor: overlay),
            box.localToGlobal(box.size.bottomRight(Offset.zero),
                ancestor: overlay),
          ),
          Offset.zero & overlay.size,
        );
        final picked = await showOpSwapPopover(
          context,
          current: op,
          position: position,
        );
        if (picked != null) {
          s.replaceChip(parent, index, OpChip(picked));
        }
      case UnaryMinusChip(:final operand):
        // Tap on unary minus removes the minus, promoting the operand.
        s.replaceChip(parent, index, operand);
      case GroupChip():
        // Tap the group chip itself — for now just place caret inside.
        s.setCaret((chip as GroupChip).children, 0);
      case FunctionChip():
        // Tapping a function lets user pick another function (preserving args).
        final advanced =
            await ref.read(advancedFunctionsEnabledProvider.future);
        if (!context.mounted) return;
        final pick = await showFunctionPickerSheet(
          context,
          advancedEnabled: advanced,
        );
        if (pick != null) {
          final fn = chip as FunctionChip;
          // Reuse existing args; truncate/pad to new arity.
          final newArgs = List<List<ChipNode>>.generate(pick.arity, (i) {
            if (i < fn.args.length) return fn.args[i];
            return <ChipNode>[];
          });
          s.replaceChip(parent, index, FunctionChip(pick.name, newArgs));
        }
    }
  }

  void _onChipLongPress(
      List<ChipNode> parent, int index, ChipNode chip) {
    HapticFeedback.mediumImpact();
    _state!.deleteChip(parent, index);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chip deleted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openVariableSheet({
    required VariableSheetMode mode,
    required void Function(String identifier) onPick,
    String? currentIdentifier,
  }) async {
    final s = _state!;
    // Build existing var list from chips + draft metadata.
    final identifiers = <String>{};
    for (final row in s.rows) {
      _collectIdentifiers(row.chips, identifiers);
      final o = row.output;
      if (o != null) identifiers.add(o.name);
    }
    final entries = <VariableEntry>[];
    for (final id in identifiers) {
      final draft = s.draftVarMeta[id];
      if (draft != null) {
        entries.add(VariableEntry(
            draft.identifier, draft.displayLabel, draft.unit, draft.role));
      } else {
        // Infer: used in some expression -> input; used as output -> output.
        final isOutput = s.rows.any((r) => r.output?.name == id);
        entries.add(VariableEntry(
            id, id, null, isOutput ? VarRole.output : VarRole.input));
      }
    }
    final result = await showVariableSheet(
      context,
      mode: mode,
      existingVars: entries,
      reservedIdentifiers: {
        ...OpRegistry.constants.keys,
        ...OpRegistry.functions.keys,
      },
    );
    if (result == null) return;
    if (result.created != null) {
      s.draftVarMeta[result.created!.identifier] = result.created!;
      onPick(result.created!.identifier);
    } else {
      onPick(result.identifier);
    }
  }

  void _collectIdentifiers(List<ChipNode> chips, Set<String> out) {
    for (final c in chips) {
      switch (c) {
        case VarChip(:final name):
          out.add(name);
        case GroupChip(:final children):
          _collectIdentifiers(children, out);
        case FunctionChip(:final args):
          for (final a in args) {
            _collectIdentifiers(a, out);
          }
        case UnaryMinusChip(:final operand):
          _collectIdentifiers([operand], out);
        case _:
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading || _state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _state!;
    final activeRow =
        s.rows.isNotEmpty ? s.rows[s.activeRowIndex] : null;
    final activeLabel = activeRow?.output?.name ?? 'row ${s.activeRowIndex + 1}';

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Formula set name',
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          onChanged: (v) => s.name = v,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: s.history.canUndo ? s.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: s.history.canRedo ? s.redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: [
          if (s.bannerError != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.bannerError!,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (var i = 0; i < s.rows.length; i++)
                  _buildRow(s, i),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add formula'),
                  onPressed: s.addRow,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          Palette(
            activeRowLabel: activeLabel,
            isOperatorContext: _isOperatorContext(),
            existingVarChips: _existingVarChips(),
            onAppendDigit: (d) => s.appendDigit(d),
            onToggleSign: () {
              // simple: wrap current row in unary minus or insert at caret
              s.insertAtCaret(const NumberChip('-'));
            },
            onScientificE: () => s.appendDigit('e'),
            onOpenGroup: s.insertGroup,
            onCloseGroup: s.closeContainer,
            onBackspace: s.backspace,
            onNewVariable: () => _openVariableSheet(
              mode: VariableSheetMode.insert,
              onPick: (id) => s.insertAtCaret(VarChip(id)),
            ),
            onInsertVarChip: (id) => s.insertAtCaret(VarChip(id)),
            onOperator: (op) => s.insertAtCaret(OpChip(op)),
            onFunctionPicked: (pick) =>
                s.insertFunction(pick.name, arity: pick.arity),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(EditorState s, int index) {
    final row = s.rows[index];
    final isActive = index == s.activeRowIndex;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => s.setActiveRow(index),
      child: Card(
        elevation: isActive ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isActive ? scheme.primary : scheme.outlineVariant,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Formula ${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                        fontWeight: FontWeight.w600,
                      )),
                  const Spacer(),
                  if (s.rows.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 18,
                      tooltip: 'Delete this formula',
                      onPressed: () => s.deleteRow(index),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _outputChip(s, index),
                  const SizedBox(width: 6),
                  Text('=',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          color: scheme.outline)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ChipRenderer(
                        chips: row.chips,
                        caret: isActive ? row.caret : null,
                        onCaretTap: (parent, idx) {
                          s.setActiveRow(index);
                          s.setCaret(parent, idx);
                        },
                        onChipTap: (parent, idx, chip) {
                          s.setActiveRow(index);
                          _onChipTap(parent, idx, chip);
                        },
                        onChipLongPress: (parent, idx, chip) {
                          s.setActiveRow(index);
                          _onChipLongPress(parent, idx, chip);
                        },
                        roleOf: _roleOf,
                      ),
                    ),
                  ),
                ],
              ),
              if (row.rowError != null) ...[
                const SizedBox(height: 6),
                Text(row.rowError!,
                    style: TextStyle(
                        fontSize: 12, color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _outputChip(EditorState s, int rowIndex) {
    final row = s.rows[rowIndex];
    final scheme = Theme.of(context).colorScheme;
    if (row.output == null) {
      return InkWell(
        onTap: () => _openVariableSheet(
          mode: VariableSheetMode.output,
          onPick: (id) => s.setOutput(rowIndex, VarChip(id)),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outline,
              style: BorderStyle.solid,
              width: 1,
            ),
          ),
          child: Text(
            'pick…',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: scheme.outline,
                fontStyle: FontStyle.italic),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _openVariableSheet(
        mode: VariableSheetMode.output,
        onPick: (id) => s.setOutput(rowIndex, VarChip(id)),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          row.output!.name,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }

  VarRole? _roleOf(String identifier) {
    final s = _state!;
    final draft = s.draftVarMeta[identifier];
    if (draft != null) return draft.role;
    if (s.rows.any((r) => r.output?.name == identifier)) return VarRole.output;
    return VarRole.input;
  }

  bool _isOperatorContext() {
    final s = _state!;
    final row = s.active;
    final caret = row.caret ??
        CaretPath(parent: row.chips, index: row.chips.length);
    if (caret.index == 0) return false;
    final prev = caret.parent[caret.index - 1];
    return switch (prev) {
      NumberChip() => true,
      VarChip() => true,
      ConstChip() => true,
      GroupChip() => true,
      FunctionChip() => true,
      _ => false,
    };
  }

  List<({String identifier, bool isInput})> _existingVarChips() {
    final s = _state!;
    final identifiers = <String>{};
    for (final row in s.rows) {
      _collectIdentifiers(row.chips, identifiers);
    }
    return identifiers.map((id) {
      final isOutput = s.rows.any((r) => r.output?.name == id);
      return (identifier: id, isInput: !isOutput);
    }).toList();
  }
}

