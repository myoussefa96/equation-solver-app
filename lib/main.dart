// Minimum-viable Flutter UI on top of the pure-Dart engine.
// Three screens: folder list → entry list → solve form. Read-only viewer of
// the 15 legacy formulas imported from the Django dump. No editing, no
// folder/entry creation, no scientific palette — see Plans 2 + 3 for the
// full design.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/engine/legacy_importer.dart';
import 'package:equation_solver_app/engine/parsed_entry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final seedJson = await rootBundle.loadString('assets/migration_seed.json');
  final seed = jsonDecode(seedJson) as Map<String, Object?>;
  final report = LegacyImporter.importSeedWithReport(seed);
  runApp(EquationSolverApp(folders: report.folders, skipped: report.skipped));
}

class EquationSolverApp extends StatelessWidget {
  const EquationSolverApp({
    super.key,
    required this.folders,
    required this.skipped,
  });

  final List<ParsedFolder> folders;
  final List<SkippedEntry> skipped;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equation Solver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: FolderListScreen(folders: folders, skipped: skipped),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1: Folder list
// ---------------------------------------------------------------------------

class FolderListScreen extends StatelessWidget {
  const FolderListScreen({
    super.key,
    required this.folders,
    required this.skipped,
  });

  final List<ParsedFolder> folders;
  final List<SkippedEntry> skipped;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = folders.where((f) => f.entries.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          if (skipped.isNotEmpty)
            IconButton(
              tooltip: "${skipped.length} formulas couldn't be imported",
              icon: const Icon(Icons.warning_amber_outlined),
              onPressed: () => _showSkipped(context, skipped),
            ),
        ],
      ),
      body: nonEmpty.isEmpty
          ? const Center(child: Text('No formulas available.'))
          : ListView.separated(
              itemCount: nonEmpty.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final folder = nonEmpty[i];
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  subtitle: Text('${folder.entries.length} formulas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EntryListScreen(folder: folder),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showSkipped(BuildContext context, List<SkippedEntry> skipped) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Formulas not imported'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in skipped) ...[
                Text(s.entryName,
                    style: const TextStyle(fontWeight: FontWeight.bold),),
                Text(s.reason, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 2: Entry list within a folder
// ---------------------------------------------------------------------------

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({super.key, required this.folder});

  final ParsedFolder folder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      body: ListView.separated(
        itemCount: folder.entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final entry = folder.entries[i];
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
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SolveScreen(entry: entry),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3: Solve form for one entry
// ---------------------------------------------------------------------------

class SolveScreen extends StatefulWidget {
  const SolveScreen({super.key, required this.entry});

  final ParsedEntry entry;

  @override
  State<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends State<SolveScreen> {
  late final List<ParsedVariable> _inputs;
  late final Map<String, TextEditingController> _controllers;
  final _formKey = GlobalKey<FormState>();
  Map<String, double>? _results;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _inputs = widget.entry.variables
        .where((v) => v.role == VarRole.input)
        .toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    _controllers = {
      for (final v in _inputs) v.identifier: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _solve() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scope = <String, double>{};
    for (final v in _inputs) {
      // Catches the European decimal-comma habit ("1,4" -> "1.4").
      final text =
          _controllers[v.identifier]!.text.trim().replaceAll(',', '.');
      scope[v.identifier] = double.parse(text);
    }
    try {
      final equations = widget.entry.equations
          .map((e) => EqEntry(output: e.outputVar, ast: e.ast))
          .toList();
      final resolved = DependencyResolver.resolve(equations);
      for (final outputName in resolved.order) {
        final eq = widget.entry.equations
            .firstWhere((e) => e.outputVar == outputName);
        scope[outputName] = Evaluator(scope: scope).eval(eq.ast);
      }
      setState(() {
        _results = Map<String, double>.fromEntries(
          widget.entry.variables
              .where((v) => v.role == VarRole.output)
              .map((v) => MapEntry(
                    v.identifier,
                    scope[v.identifier] ?? double.nan,
                  ),),
        );
        _errorMessage = null;
      });
    } on EngineError catch (e) {
      setState(() {
        _results = null;
        _errorMessage = e.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final finalOutputs = widget.entry.variables
        .where((v) => v.role == VarRole.output && v.isFinal)
        .toList();
    final otherOutputs = widget.entry.variables
        .where((v) => v.role == VarRole.output && !v.isFinal)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.entry.description != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.entry.description!,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Enter values',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final v in _inputs) ...[
                TextFormField(
                  controller: _controllers[v.identifier],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: v.displayLabel,
                    helperText: v.unit,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a value';
                    }
                    final normalized = value.trim().replaceAll(',', '.');
                    if (double.tryParse(normalized) == null) {
                      return 'Numbers only — try "1.4" instead of "1,4"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _solve,
                icon: const Icon(Icons.calculate),
                label: const Text('Solve'),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              if (_results != null) ...[
                const Text(
                  'Result',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final v in finalOutputs)
                  _resultTile(context, v, _results![v.identifier],
                      emphasis: true,),
                if (otherOutputs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Intermediate values',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  for (final v in otherOutputs)
                    _resultTile(context, v, _results![v.identifier]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultTile(
    BuildContext context,
    ParsedVariable v,
    double? value, {
    bool emphasis = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: emphasis ? scheme.primaryContainer : null,
      child: ListTile(
        title: Text(
          v.displayLabel,
          style: TextStyle(
            fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: v.unit == null ? null : Text(v.unit!),
        trailing: Text(
          value == null ? '—' : _format(value),
          style: TextStyle(
            fontSize: emphasis ? 22 : 16,
            fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
            color: emphasis ? scheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }

  String _format(double v) {
    if (v == 0) return '0';
    final abs = v.abs();
    if (abs >= 1e6 || abs < 1e-3) {
      return v.toStringAsExponential(4);
    }
    return v
        .toStringAsPrecision(6)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
