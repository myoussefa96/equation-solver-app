import 'ast.dart';

/// Serialize an AST node to a JSON-safe Map.
Map<String, Object?> astToJson(AstNode node) {
  return switch (node) {
    NumberLit(:final value) => {'type': 'NumberLit', 'value': value},
    Identifier(:final name) => {'type': 'Identifier', 'name': name},
    UnaryMinus(:final operand) => {
        'type': 'UnaryMinus',
        'operand': astToJson(operand),
      },
    BinaryOp(:final op, :final left, :final right) => {
        'type': 'BinaryOp',
        'op': op,
        'left': astToJson(left),
        'right': astToJson(right),
      },
    FunctionCall(:final name, :final args) => {
        'type': 'FunctionCall',
        'name': name,
        'args': args.map(astToJson).toList(),
      },
  };
}

/// Deserialize a JSON Map back to an AST node.
/// Throws [FormatException] if the structure is malformed.
AstNode astFromJson(Map<String, Object?> json) {
  final type = json['type'];
  return switch (type) {
    'NumberLit' => NumberLit((json['value'] as num).toDouble()),
    'Identifier' => Identifier(json['name'] as String),
    'UnaryMinus' => UnaryMinus(
        astFromJson(json['operand']! as Map<String, Object?>),),
    'BinaryOp' => BinaryOp(
        json['op'] as String,
        astFromJson(json['left']! as Map<String, Object?>),
        astFromJson(json['right']! as Map<String, Object?>),
      ),
    'FunctionCall' => FunctionCall(
        json['name'] as String,
        (json['args']! as List)
            .map((a) => astFromJson(a as Map<String, Object?>))
            .toList(),
      ),
    _ => throw FormatException('Unknown AST node type: $type'),
  };
}

// Operator precedence table — higher = tighter binding.
// Used by the pretty-printer to decide where parens are needed.
const Map<String, int> _opPrec = {'+': 1, '-': 1, '*': 2, '/': 2, '^': 3};
const Set<String> _rightAssoc = {'^'};

/// Pretty-print an AST back to formula text. Inverse of the parser:
/// `prettyPrint(astFromJson(astToJson(parser.parse(text))))` ≈ `text` modulo whitespace.
String prettyPrint(AstNode node) {
  return switch (node) {
    NumberLit(:final value) => value.toString(),
    Identifier(:final name) => name,
    UnaryMinus(:final operand) => '-${_wrapForUnary(operand)}',
    BinaryOp(:final op, :final left, :final right) =>
      '${_wrapForBinary(left, op, isLeft: true)} $op '
      '${_wrapForBinary(right, op, isLeft: false)}',
    FunctionCall(:final name, :final args) =>
      '$name(${args.map(prettyPrint).join(', ')})',
  };
}

String _wrapForBinary(AstNode child, String parentOp, {required bool isLeft}) {
  if (child is BinaryOp) {
    final childPrec = _opPrec[child.op]!;
    final parentPrec = _opPrec[parentOp]!;
    if (childPrec < parentPrec) return '(${prettyPrint(child)})';
    if (childPrec == parentPrec) {
      // Same precedence: right-assoc ops need parens on the LEFT child;
      // left-assoc ops need parens on the RIGHT child.
      final rightAssoc = _rightAssoc.contains(parentOp);
      final needsParens = rightAssoc ? isLeft : !isLeft;
      if (needsParens) return '(${prettyPrint(child)})';
    }
  }
  return prettyPrint(child);
}

String _wrapForUnary(AstNode child) {
  if (child is BinaryOp) return '(${prettyPrint(child)})';
  return prettyPrint(child);
}
