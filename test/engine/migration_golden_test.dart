import 'dart:convert';
import 'dart:io';
import 'package:equation_solver_app/engine/ast_json.dart';
import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/engine/legacy_importer.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:equation_solver_app/engine/parsed_entry.dart';
import 'package:test/test.dart';

void main() {
  late ImportReport report;

  setUpAll(() {
    final raw = File('assets/migration_seed.json').readAsStringSync();
    final seed = jsonDecode(raw) as Map<String, Object?>;
    report = LegacyImporter.importSeedWithReport(seed);
  });

  test('all 15 legacy formulas import without being skipped', () {
    final imported =
        report.folders.fold<int>(0, (n, f) => n + f.entries.length);
    expect(
      imported,
      equals(15),
      reason: 'expected 15 imported, got $imported. Skipped: '
          '${report.skipped.map((s) => "${s.entryName}: ${s.reason}").join('; ')}',
    );
    expect(report.skipped, isEmpty);
  });

  test('every imported formula smoke-evaluates with 1.0 inputs', () {
    final whitelist = <String>{
      // C=1 → C^(-0.57)=1 > 0.9694, so inner sqrt argument is negative.
      'injection ratio U',
      // K=1 → (K-1)=0, division by zero in 2/(K-1) inside the sqrt argument.
      ' Nozzle Exit Mach Number',
      // K=1 → (K-1)=0, division by zero in the exponent -K/(K-1).
      'Isentropic - Pressure Ratio',
      // K=1 → (K-1)=0, division by zero in the exponent (K+1)/(2*(K-1)).
      'Isentropic - Area Ratio',
    };
    final failures = <String>[];
    for (final folder in report.folders) {
      for (final entry in folder.entries) {
        try {
          _smokeEvaluate(entry);
        } on Exception catch (e) {
          if (!whitelist.contains(entry.name)) {
            failures.add('${entry.name}: $e');
          }
        }
      }
    }
    expect(failures, isEmpty);
  });

  test('AST pretty-print → parse round-trip yields equal AST', () {
    for (final folder in report.folders) {
      for (final entry in folder.entries) {
        for (final eq in entry.equations) {
          final printed = prettyPrint(eq.ast);
          final reparsed = Parser(printed).parseExpression();
          expect(
            reparsed,
            equals(eq.ast),
            reason: 'round-trip failed for "${entry.name}" / ${eq.outputVar} '
                '— printed: $printed',
          );
        }
      }
    }
  });
}

/// Substitutes 1.0 for every input-role variable, then evaluates each equation
/// in topo order. Throws if any equation evaluates to NaN/Inf or an EngineError.
void _smokeEvaluate(ParsedEntry entry) {
  final inputs = entry.variables
      .where((v) => v.role == VarRole.input)
      .map((v) => v.identifier);
  final scope = <String, double>{for (final id in inputs) id: 1.0};

  // We need topo order: re-run the resolver on these equations.
  final eqs = entry.equations
      .map((e) => EqEntry(output: e.outputVar, ast: e.ast))
      .toList();
  final resolved = DependencyResolver.resolve(eqs);

  for (final outputName in resolved.order) {
    final eq = entry.equations.firstWhere((e) => e.outputVar == outputName);
    final v = Evaluator(scope: scope).eval(eq.ast);
    scope[outputName] = v;
  }
}
