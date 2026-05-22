import 'dart:math' as math;
import 'ast.dart';
import 'errors.dart';
import 'op_registry.dart';

class Evaluator {
  const Evaluator({this.scope = const {}});

  final Map<String, double> scope;

  /// Evaluate an AST. Throws an [EngineError] subclass on failure.
  double eval(AstNode node) {
    final v = _evalInternal(node);
    if (v.isNaN || v.isInfinite) {
      throw EvalError(
        'Result is undefined (likely a divide-by-zero or out-of-range value upstream).',
        node,
      );
    }
    return v;
  }

  double _evalInternal(AstNode node) {
    return switch (node) {
      NumberLit(:final value) => value,
      Identifier(:final name) => _lookup(name),
      UnaryMinus(:final operand) => -_evalInternal(operand),
      BinaryOp(:final op, :final left, :final right) =>
        _applyBinary(op, _evalInternal(left), _evalInternal(right), node),
      FunctionCall(:final name, :final args) =>
        _applyFunction(name, args.map(_evalInternal).toList(growable: false), node),
    };
  }

  double _lookup(String name) {
    if (scope.containsKey(name)) return scope[name]!;
    final c = OpRegistry.constants[name];
    if (c != null) return c;
    throw UnknownIdentifierError(name);
  }

  double _applyBinary(String op, double a, double b, AstNode location) {
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '*': return a * b;
      case '/':
        if (b == 0) throw EvalError('Can\'t divide by zero.', location);
        return a / b;
      case '^':
        if (a == 0 && b < 0) {
          throw EvalError('Can\'t raise 0 to a negative power.', location);
        }
        if (a < 0 && b != b.roundToDouble()) {
          throw EvalError(
            'Can\'t raise a negative number ($a) to a non-integer power ($b).',
            location,
          );
        }
        return math.pow(a, b).toDouble();
      default:
        throw EvalError('Unknown operator "$op".', location);
    }
  }

  double _applyFunction(String name, List<double> args, AstNode location) {
    final def = OpRegistry.lookup(name);
    if (def == null) {
      throw EvalError('"$name" isn\'t a function the app knows about.', location);
    }
    if (def.arity != -1 && def.arity != args.length) {
      throw EvalError(
        '"$name" needs ${def.arity} argument(s) but got ${args.length}.',
        location,
      );
    }
    if (name == 'sqrt' || name == 'root') {
      if (args[0] < 0) {
        throw EvalError('Can\'t take the square root of ${args[0]}.', location);
      }
    }
    if (name == 'ln' || name == 'log') {
      if (args[0] <= 0) {
        throw EvalError('Can\'t take the logarithm of ${args[0]}.', location);
      }
    }
    return def.impl(args);
  }
}
