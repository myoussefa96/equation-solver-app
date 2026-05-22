import 'package:meta/meta.dart';

@immutable
sealed class AstNode {
  const AstNode();
}

@immutable
class NumberLit extends AstNode {
  const NumberLit(this.value);
  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is NumberLit && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberLit($value)';
}

@immutable
class Identifier extends AstNode {
  const Identifier(this.name);
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Identifier && other.name == name);

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Identifier($name)';
}

@immutable
class UnaryMinus extends AstNode {
  const UnaryMinus(this.operand);
  final AstNode operand;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UnaryMinus && other.operand == operand);

  @override
  int get hashCode => Object.hash('unary-', operand);

  @override
  String toString() => 'UnaryMinus($operand)';
}

@immutable
class BinaryOp extends AstNode {
  const BinaryOp(this.op, this.left, this.right);
  final String op; // one of: + - * / ^
  final AstNode left;
  final AstNode right;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BinaryOp && other.op == op && other.left == left && other.right == right);

  @override
  int get hashCode => Object.hash(op, left, right);

  @override
  String toString() => 'BinaryOp($op, $left, $right)';
}

@immutable
class FunctionCall extends AstNode {
  const FunctionCall(this.name, this.args);
  final String name;
  final List<AstNode> args;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FunctionCall) return false;
    if (other.name != name || other.args.length != args.length) return false;
    for (var i = 0; i < args.length; i++) {
      if (other.args[i] != args[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(args));

  @override
  String toString() => 'FunctionCall($name, $args)';
}
