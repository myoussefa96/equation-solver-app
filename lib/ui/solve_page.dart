import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/state/entry_detail_provider.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/widgets/result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _initialised = {};

  Map<String, double>? _results;
  String? _errorMessage;
  String? _errorOutputIdentifier;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String identifier, double? lastValue) {
    if (!_controllers.containsKey(identifier)) {
      _controllers[identifier] =
          TextEditingController(text: lastValue?.toString() ?? '');
      _initialised.add(identifier);
    } else if (!_initialised.contains(identifier)) {
      _controllers[identifier]!.text = lastValue?.toString() ?? '';
      _initialised.add(identifier);
    }
    return _controllers[identifier]!;
  }

  Future<void> _solve(EntryDetail detail) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final inputs =
        detail.variables.where((v) => v.role == VarRole.input).toList()
          ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));

    final scope = <String, double>{};
    for (final v in inputs) {
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
        try {
          scope[outputName] = Evaluator(scope: scope).eval(eq.ast);
        } on EngineError catch (e) {
          throw _SolveFailure(outputName, e);
        }
      }

      final repo = ref.read(variableMetaRepoProvider);
      for (final v in inputs) {
        await repo.updateLastValue(
            widget.entryId, v.identifier, scope[v.identifier]!);
      }
      ref.invalidate(entryDetailProvider(widget.entryId));

      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _results = {
            for (final v
                in detail.variables.where((v) => v.role == VarRole.output))
              v.identifier: scope[v.identifier] ?? double.nan,
          };
          _errorMessage = null;
          _errorOutputIdentifier = null;
        });
      }
    } on _SolveFailure catch (sf) {
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _results = {};
          _errorMessage = sf.engineError.userMessage;
          _errorOutputIdentifier = sf.outputName;
        });
      }
    } on EngineError catch (e) {
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _results = null;
          _errorMessage = e.userMessage;
          _errorOutputIdentifier = null;
        });
      }
    }
  }

  void _resetInputs(List<VariableMetaRow> inputs) {
    for (final v in inputs) {
      _controllers[v.identifier]?.text = v.lastValue?.toString() ?? '';
    }
    setState(() {
      _results = null;
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inputs reset to last saved values')),
    );
  }

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
    final inputs =
        detail.variables.where((v) => v.role == VarRole.input).toList()
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
            _sectionLabel(context, 'Formula'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final eq in detail.equations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${eq.outputVar} = ${_renderAst(eq.ast)}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Enter values'),
            for (final v in inputs) ...[
              TextFormField(
                controller: _controllerFor(v.identifier, v.lastValue),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _solve(detail),
                    icon: const Icon(Icons.calculate),
                    label: const Text('Solve'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _resetInputs(inputs),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null && _errorOutputIdentifier == null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            if (_results != null || _errorOutputIdentifier != null) ...[
              _sectionLabel(context, 'Result'),
              for (final v in finalOutputs)
                ResultTile(
                  variable: v,
                  value: _results?[v.identifier],
                  emphasis: true,
                  errorMessage: v.identifier == _errorOutputIdentifier
                      ? _errorMessage
                      : null,
                ),
              if (otherOutputs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Intermediate values',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                for (final v in otherOutputs)
                  ResultTile(
                    variable: v,
                    value: _results?[v.identifier],
                    errorMessage: v.identifier == _errorOutputIdentifier
                        ? _errorMessage
                        : null,
                  ),
              ],
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  static String _renderAst(AstNode n) {
    return switch (n) {
      NumberLit(:final value) => value.toString(),
      Identifier(:final name) => name,
      UnaryMinus(:final operand) => '-${_renderAst(operand)}',
      BinaryOp(:final op, :final left, :final right) =>
        '(${_renderAst(left)} $op ${_renderAst(right)})',
      FunctionCall(:final name, :final args) =>
        '$name(${args.map(_renderAst).join(', ')})',
    };
  }
}

class _SolveFailure implements Exception {
  _SolveFailure(this.outputName, this.engineError);
  final String outputName;
  final EngineError engineError;
}
