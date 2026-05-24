import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/op_registry.dart';

sealed class ChipNode {
  const ChipNode();
}

class NumberChip extends ChipNode {
  const NumberChip(this.text);
  final String text;
  @override
  String toString() => 'NumberChip($text)';
  @override
  bool operator ==(Object o) => o is NumberChip && o.text == text;
  @override
  int get hashCode => text.hashCode;
}

class VarChip extends ChipNode {
  const VarChip(this.name);
  final String name;
  @override
  String toString() => 'VarChip($name)';
  @override
  bool operator ==(Object o) => o is VarChip && o.name == name;
  @override
  int get hashCode => name.hashCode;
}

class ConstChip extends ChipNode {
  const ConstChip(this.name);
  final String name;
  @override
  String toString() => 'ConstChip($name)';
  @override
  bool operator ==(Object o) => o is ConstChip && o.name == name;
  @override
  int get hashCode => name.hashCode;
}

class OpChip extends ChipNode {
  const OpChip(this.op);
  final String op;
  @override
  String toString() => 'OpChip($op)';
  @override
  bool operator ==(Object o) => o is OpChip && o.op == op;
  @override
  int get hashCode => op.hashCode;
}

class UnaryMinusChip extends ChipNode {
  const UnaryMinusChip(this.operand);
  final ChipNode operand;
  @override
  String toString() => 'UnaryMinusChip($operand)';
  @override
  bool operator ==(Object o) => o is UnaryMinusChip && o.operand == operand;
  @override
  int get hashCode => operand.hashCode;
}

class GroupChip extends ChipNode {
  const GroupChip(this.children);
  final List<ChipNode> children;
  @override
  String toString() => 'GroupChip($children)';
  @override
  bool operator ==(Object o) =>
      o is GroupChip && _listEq(o.children, children);
  @override
  int get hashCode => Object.hashAll(children);
}

class FunctionChip extends ChipNode {
  const FunctionChip(this.name, this.args);
  final String name;
  final List<List<ChipNode>> args;
  @override
  String toString() => 'FunctionChip($name, $args)';
  @override
  bool operator ==(Object o) {
    if (o is! FunctionChip || o.name != name || o.args.length != args.length) {
      return false;
    }
    for (var i = 0; i < args.length; i++) {
      if (!_listEq(o.args[i], args[i])) return false;
    }
    return true;
  }
  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(args.map(Object.hashAll)));
}

bool _listEq(List<ChipNode> a, List<ChipNode> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Caret {
  Caret({required this.parent, required this.index});
  final List<ChipNode> parent;
  final int index;
}

String flatten(List<ChipNode> chips) {
  final buf = StringBuffer();
  for (final c in chips) {
    buf.write(_flattenOne(c));
  }
  return buf.toString();
}

String _flattenOne(ChipNode c) {
  return switch (c) {
    NumberChip(:final text) => text,
    VarChip(:final name) => name,
    ConstChip(:final name) => name,
    OpChip(:final op) => ' $op ',
    UnaryMinusChip(:final operand) => '-${_flattenOne(operand)}',
    GroupChip(:final children) => '(${flatten(children)})',
    FunctionChip(:final name, :final args) =>
      '$name(${args.map(flatten).join(', ')})',
  };
}

List<ChipNode> chipsFromAst(AstNode n) {
  return switch (n) {
    NumberLit(:final value) => [NumberChip(_formatNumber(value))],
    Identifier(:final name) when OpRegistry.constants.containsKey(name) => [
        ConstChip(name)
      ],
    Identifier(:final name) => [VarChip(name)],
    UnaryMinus(:final operand) => [UnaryMinusChip(_asAtom(operand))],
    BinaryOp(:final left, :final op, :final right) => [
        ..._wrapForBinarySide(left),
        OpChip(op),
        ..._wrapForBinarySide(right),
      ],
    FunctionCall(:final name, :final args) => [
        FunctionChip(name, args.map(chipsFromAst).toList()),
      ],
  };
}

String _formatNumber(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

ChipNode _asAtom(AstNode n) {
  final list = chipsFromAst(n);
  if (list.length == 1) return list[0];
  return GroupChip(list);
}

List<ChipNode> _wrapForBinarySide(AstNode n) {
  return switch (n) {
    BinaryOp() => [GroupChip(chipsFromAst(n))],
    _ => chipsFromAst(n),
  };
}

List<ChipNode> insertAt(List<ChipNode> list, Caret caret, ChipNode chip) {
  final copy = List<ChipNode>.from(list);
  copy.insert(caret.index, chip);
  return copy;
}

List<ChipNode> backspaceAt(List<ChipNode> list, Caret caret) {
  if (caret.index == 0) return list;
  final copy = List<ChipNode>.from(list);
  copy.removeAt(caret.index - 1);
  return copy;
}
