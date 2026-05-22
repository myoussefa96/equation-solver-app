import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SolvePage extends ConsumerStatefulWidget {
  const SolvePage({
    super.key,
    required this.entryId,
    required this.entryName,
  });

  final int entryId;
  final String entryName;

  @override
  ConsumerState<SolvePage> createState() => _SolvePageState();
}

class _SolvePageState extends ConsumerState<SolvePage> {
  final _formKey = GlobalKey<FormState>();

  /// Controllers keyed by variable identifier; pre-filled once from lastValue.
  final Map<String, TextEditingController> _controllers = {};

  /// Track identifiers that have already been pre-filled so we do it only once.
  final Set<String> _initialised = {};

  Map<String, double>? _results;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controller management
  // ---------------------------------------------------------------------------

  /// Returns (creating if necessary) the controller for [identifier],
  /// pre-filling with [lastValue] the first time it is seen.
  TextEditingController _controllerFor(String identifier, double? lastValue) {
    if (!_controllers.containsKey(identifier)) {
      _controllers[identifier] = TextEditingController(
        text: lastValue?.toString() ?? '',
      );
      _initialised.add(identifier);
    } else if (!_initialised.contains(identifier)) {
      _controllers[identifier]!.text = lastValue?.toString() ?? '';
      _initialised.add(identifier);
    }
    return _controllers[identifier]!;
  }

  // ---------------------------------------------------------------------------
  // Solve
  // ---------------------------------------------------------------------------

  Future<void> _solve(EntryDetail detail) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final inputs = detail.variables
        .where((v) => v.role == VarRole.input)
        .toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));

    final scope = <String, double>{};
    for (final v in inputs) {
      // European decimal-comma support: "1,4" -> "1.4"
      final text =
          _controllers[v.identifier]!.text.trim().replaceAll(',', '.');
      scope[v.identifier] = double.parse(text);
    }

    try {
      final equations = detail.equations
          .map((e) => EqEntry(output: e.outputVar, ast: e.ast))
          .toList();
      final resolved = DependencyResolver.resolve(equations);

      for (final outputName in resolved.order) {
        final eq =
            detail.equations.firstWhere((e) => e.outputVar == outputName);
        scope[outputName] = Evaluator(scope: scope).eval(eq.ast);
      }

      // Persist last_value for each input.
      final repo = ref.read(variableMetaRepoProvider);
      for (final v in inputs) {
        await repo.updateLastValue(
          widget.entryId,
          v.identifier,
          scope[v.identifier]!,
        );
      }
      // Invalidate so next open pre-fills the updated values.
      ref.invalidate(entryDetailProvider(widget.entryId));

      if (mounted) {
        setState(() {
          _results = Map<String, double>.fromEntries(
            detail.variables
                .where((v) => v.role == VarRole.output)
                .map(
                  (v) => MapEntry(
                    v.identifier,
                    scope[v.identifier] ?? double.nan,
                  ),
                ),
          );
          _errorMessage = null;
        });
      }
    } on EngineError catch (e) {
      if (mounted) {
        setState(() {
          _results = null;
          _errorMessage = e.userMessage;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(entryDetailProvider(widget.entryId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.entryName)),
      body: asyncDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load: $err')),
        data: (detail) => _buildForm(context, detail),
      ),
    );
  }

  Widget _buildForm(BuildContext context, EntryDetail detail) {
    final inputs = detail.variables
        .where((v) => v.role == VarRole.input)
        .toList()
      ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));

    final finalOutputs = detail.variables
        .where((v) => v.role == VarRole.output && v.isFinal)
        .toList();
    final otherOutputs = detail.variables
        .where((v) => v.role == VarRole.output && !v.isFinal)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter values',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final v in inputs) ...[
              TextFormField(
                controller: _controllerFor(v.identifier, v.lastValue),
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
              onPressed: () => _solve(detail),
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
                _resultTile(
                  context,
                  v,
                  _results![v.identifier],
                  emphasis: true,
                ),
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
    );
  }

  // ---------------------------------------------------------------------------
  // Result tile (mirrors MVP _resultTile)
  // ---------------------------------------------------------------------------

  Widget _resultTile(
    BuildContext context,
    VariableMetaRow v,
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

  // ---------------------------------------------------------------------------
  // Format helper (mirrors MVP _format)
  // ---------------------------------------------------------------------------

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
