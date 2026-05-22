import 'package:meta/meta.dart';
import 'ast.dart';
import 'errors.dart';
import 'op_registry.dart';

enum VarRole { input, intermediate, output }

@immutable
class EqEntry {
  const EqEntry({required this.output, required this.ast});

  final String output;
  final AstNode ast;
}

@immutable
class ResolveResult {
  const ResolveResult(this.order, this.roles);

  final List<String> order;                  // topo-sorted output names
  final Map<String, VarRole> roles;          // every non-constant identifier
}

abstract final class DependencyResolver {
  /// Resolve dependencies for a set of equations belonging to one entry.
  ///
  /// [declaredVariables] is the set of identifiers the user has declared via
  /// the builder's "Add a variable" sheet, mapped to their roles if known
  /// (null = unknown; resolver will classify). Pass `{}` if you only want to
  /// classify based on AST usage.
  ///
  /// Returns the topo-sorted output order and role map.
  /// Throws [CycleError] or [DuplicateOutputError].
  static ResolveResult resolve(
    List<EqEntry> equations, {
    Map<String, VarRole?> declaredVariables = const {},
  }) {
    // 1. Check for duplicate outputs.
    final seen = <String>{};
    for (final e in equations) {
      if (!seen.add(e.output)) {
        throw DuplicateOutputError(e.output);
      }
    }

    // 2. Collect every referenced identifier (excluding constants).
    final refs = <String, Set<String>>{}; // output -> set of identifiers in its RHS
    final allIds = <String>{};
    for (final e in equations) {
      final ids = _collectIds(e.ast);
      refs[e.output] = ids;
      allIds.addAll(ids);
      allIds.add(e.output);
    }
    allIds.addAll(declaredVariables.keys);

    // 3. Build outputs set (= LHS of all equations).
    final outputs = equations.map((e) => e.output).toSet();

    // 4. Build edges: rhs-id -> lhs (only if rhs-id is also a LHS of some equation).
    final edgesOut = <String, Set<String>>{
      for (final e in equations) e.output: <String>{},
    };
    final inDegree = <String, int>{
      for (final e in equations) e.output: 0,
    };
    for (final e in equations) {
      for (final id in refs[e.output]!) {
        if (outputs.contains(id)) {
          edgesOut[id]!.add(e.output);
          inDegree[e.output] = inDegree[e.output]! + 1;
        }
      }
    }

    // 5. Kahn's algorithm.
    final queue = <String>[
      for (final e in equations)
        if (inDegree[e.output] == 0) e.output,
    ];
    final order = <String>[];
    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      order.add(n);
      for (final m in edgesOut[n]!) {
        inDegree[m] = inDegree[m]! - 1;
        if (inDegree[m] == 0) queue.add(m);
      }
    }

    if (order.length != equations.length) {
      // Cycle exists. Collect remaining nodes for the message.
      final remaining = [
        for (final e in equations)
          if (inDegree[e.output]! > 0) e.output,
      ];
      throw CycleError(remaining);
    }

    // 6. Classify roles.
    final roles = <String, VarRole>{};
    for (final id in allIds) {
      if (OpRegistry.constants.containsKey(id)) continue;
      final isOutput = outputs.contains(id);
      if (!isOutput) {
        roles[id] = VarRole.input;
        continue;
      }
      // It's an output. Determine if any later equation references it.
      final referencedByOther = equations
          .where((e) => e.output != id)
          .any((e) => refs[e.output]!.contains(id));
      roles[id] = referencedByOther ? VarRole.intermediate : VarRole.output;
    }

    return ResolveResult(order, roles);
  }

  static Set<String> _collectIds(AstNode node) {
    final out = <String>{};
    void walk(AstNode n) {
      switch (n) {
        case NumberLit():
          break;
        case Identifier(:final name):
          if (!OpRegistry.constants.containsKey(name)) out.add(name);
          break;
        case UnaryMinus(:final operand):
          walk(operand);
          break;
        case BinaryOp(:final left, :final right):
          walk(left);
          walk(right);
          break;
        case FunctionCall(:final args):
          for (final a in args) {
            walk(a);
          }
          break;
      }
    }
    walk(node);
    return out;
  }
}
