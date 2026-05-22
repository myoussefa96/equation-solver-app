import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:equation_solver_app/engine/slugify.dart';
import 'package:equation_solver_app/state/entries_provider.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/equations_repo.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter/material.dart';
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

class _FormulaRow {
  _FormulaRow({String? output, String? expr})
      : outputCtrl = TextEditingController(text: output ?? ''),
        exprCtrl = TextEditingController(text: expr ?? '');

  final TextEditingController outputCtrl;
  final TextEditingController exprCtrl;
  String? error;

  void dispose() {
    outputCtrl.dispose();
    exprCtrl.dispose();
  }
}

class _EntryEditorPageState extends ConsumerState<EntryEditorPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rows = <_FormulaRow>[_FormulaRow()];
  String? _bannerError;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.entryId != null) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final entries = ref.read(entriesRepoProvider);
    final entry = await entries.getById(widget.entryId!);
    if (entry == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final detail = await ref.read(entryDetailProvider(widget.entryId!).future);
    _nameCtrl.text = entry.name;
    _descCtrl.text = entry.description ?? '';
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    for (final eq in detail.equations) {
      // Pretty-print the AST back to text for editing.
      // We avoid importing ast_json.dart's prettyPrint here to keep the
      // editor's textual surface minimal; a future block builder replaces
      // this entirely. Use a quick toString fallback. (See Note below.)
      _rows.add(_FormulaRow(
        output: eq.outputVar,
        expr: _prettyAst(eq.ast),
      ),);
    }
    if (_rows.isEmpty) _rows.add(_FormulaRow());
    setState(() => _loading = false);
  }

  String _prettyAst(AstNode n) {
    // Inline pretty-print mirroring engine/ast_json.dart's logic.
    // Kept here to avoid widening the engine's public surface.
    return switch (n) {
      NumberLit(:final value) => value.toString(),
      Identifier(:final name) => name,
      UnaryMinus(:final operand) => '-(${_prettyAst(operand)})',
      BinaryOp(:final op, :final left, :final right) =>
        '(${_prettyAst(left)} $op ${_prettyAst(right)})',
      FunctionCall(:final name, :final args) =>
        '$name(${args.map(_prettyAst).join(", ")})',
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _bannerError = null;
      _saving = true;
      for (final r in _rows) {
        r.error = null;
      }
    });

    if (_nameCtrl.text.trim().isEmpty) {
      setState(() {
        _bannerError = 'Give this formula a name.';
        _saving = false;
      });
      return;
    }

    final parsed = <_FormulaRow, _ParsedRow>{};
    for (final row in _rows) {
      final outRaw = row.outputCtrl.text.trim();
      final exprRaw = row.exprCtrl.text.trim();
      if (outRaw.isEmpty && exprRaw.isEmpty) continue;
      if (outRaw.isEmpty) {
        row.error = 'Output name is required.';
        continue;
      }
      if (exprRaw.isEmpty) {
        row.error = 'Formula is required.';
        continue;
      }
      try {
        final ast = Parser(exprRaw).parseExpression();
        parsed[row] = _ParsedRow(slugify(outRaw), outRaw, ast);
      } on FormatException catch (e) {
        row.error = e.message;
      }
    }
    if (parsed.isEmpty ||
        parsed.length !=
            _rows
                .where((r) =>
                    r.outputCtrl.text.trim().isNotEmpty ||
                    r.exprCtrl.text.trim().isNotEmpty,)
                .length) {
      setState(() {
        _bannerError = 'Fix the formula errors above before saving.';
        _saving = false;
      });
      return;
    }

    // Run dependency resolver.
    final eqEntries = parsed.values
        .map((p) => EqEntry(output: p.identifier, ast: p.ast))
        .toList();
    ResolveResult resolved;
    try {
      resolved = DependencyResolver.resolve(eqEntries);
    } on EngineError catch (e) {
      setState(() {
        _bannerError = e.userMessage;
        _saving = false;
      });
      return;
    }

    // Persist.
    final entries = ref.read(entriesRepoProvider);
    int entryId;
    if (widget.entryId == null) {
      entryId = await entries.create(
        folderId: widget.folderId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
      );
    } else {
      entryId = widget.entryId!;
      await entries.rename(entryId, _nameCtrl.text.trim());
      await entries.updateDescription(
        entryId,
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
    }

    // Write equations + variable_meta.
    final equationsRepo = ref.read(equationsRepoProvider);
    final variablesRepo = ref.read(variableMetaRepoProvider);
    final rowList = parsed.values.toList();
    await equationsRepo.replaceAll(entryId, [
      for (var i = 0; i < rowList.length; i++)
        EquationDraft(
          entryId: entryId,
          outputVar: rowList[i].identifier,
          ast: rowList[i].ast,
          sortOrder: i,
        ),
    ]);

    // Build variable metadata.
    final outputLabels = {
      for (final p in parsed.values) p.identifier: p.label,
    };
    final variables = <VariableMetaDraft>[];
    for (final entryV in resolved.roles.entries) {
      final id = entryV.key;
      final role = entryV.value;
      final label = outputLabels[id] ?? id;
      variables.add(VariableMetaDraft(
        entryId: entryId,
        identifier: id,
        displayLabel: label,
        role: role,
        isFinal: role == VarRole.output,
      ),);
    }
    await variablesRepo.replaceAll(entryId, variables);

    ref.invalidate(entriesByFolderProvider(widget.folderId));
    if (widget.entryId != null) {
      ref.invalidate(entryDetailProvider(widget.entryId!));
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryId == null ? 'New formula' : 'Edit formula'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_bannerError != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_bannerError!),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Nozzle Exit Mach Number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Formulas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each formula computes one variable. Use other variables on the right side; the app figures out the order automatically.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _rows.length; i++) ...[
            _buildRow(i),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: () => setState(() => _rows.add(_FormulaRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add formula'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRow(int i) {
    final row = _rows[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: row.outputCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Output',
                      hintText: 'e.g. Me',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '=',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: row.exprCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Expression',
                      hintText: 'e.g. sqrt(2*K + 1)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      row.dispose();
                      _rows.removeAt(i);
                    }),
                  ),
              ],
            ),
            if (row.error != null) ...[
              const SizedBox(height: 4),
              Text(row.error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParsedRow {
  _ParsedRow(this.identifier, this.label, this.ast);

  final String identifier;
  final String label;
  final AstNode ast;
}
