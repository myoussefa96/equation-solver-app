import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/ast_json.dart';
import 'package:test/test.dart';

void main() {
  group('AST JSON round-trip', () {
    void roundTrip(AstNode node) {
      final json = astToJson(node);
      final back = astFromJson(json);
      expect(back, equals(node), reason: 'round-trip failed for $node');
    }

    test('NumberLit round-trips', () => roundTrip(const NumberLit(3.14)));
    test('Identifier round-trips', () => roundTrip(const Identifier('K')));
    test('UnaryMinus round-trips', () => roundTrip(const UnaryMinus(NumberLit(2))));
    test('BinaryOp round-trips', () => roundTrip(
        const BinaryOp('+', NumberLit(1), Identifier('x'),),),);
    test('FunctionCall (single-arg) round-trips', () => roundTrip(
        const FunctionCall('sin', [Identifier('t')]),),);
    test('FunctionCall (multi-arg) round-trips', () => roundTrip(
        const FunctionCall('min', [NumberLit(1), NumberLit(2)]),),);
    test('deeply nested round-trips', () {
      // sin((a + b) ^ 2)
      const ast = FunctionCall('sin', [
        BinaryOp(
          '^',
          BinaryOp('+', Identifier('a'), Identifier('b')),
          NumberLit(2),
        ),
      ]);
      roundTrip(ast);
    });

    test('unknown type throws', () {
      expect(
        () => astFromJson({'type': 'BogusNode'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('pretty-printer', () {
    test('simple binary op renders with parens by precedence', () {
      expect(prettyPrint(const BinaryOp('+', NumberLit(1), NumberLit(2))),
          equals('1.0 + 2.0'),);
    });

    test('multiplication has higher precedence than addition', () {
      // (1 + 2) * 3 needs parens
      expect(
        prettyPrint(const BinaryOp(
          '*',
          BinaryOp('+', NumberLit(1), NumberLit(2),),
          NumberLit(3),
        ),),
        equals('(1.0 + 2.0) * 3.0'),
      );
      // 1 + 2 * 3 needs none
      expect(
        prettyPrint(const BinaryOp(
          '+',
          NumberLit(1),
          BinaryOp('*', NumberLit(2), NumberLit(3),),
        ),),
        equals('1.0 + 2.0 * 3.0'),
      );
    });

    test('function call renders with parens around args', () {
      expect(
        prettyPrint(const FunctionCall('sqrt', [Identifier('x')])),
        equals('sqrt(x)'),
      );
      expect(
        prettyPrint(const FunctionCall('min', [Identifier('a'), Identifier('b')])),
        equals('min(a, b)'),
      );
    });

    test('unary minus renders correctly', () {
      expect(prettyPrint(const UnaryMinus(Identifier('x'))), equals('-x'));
    });

    test('exponent is right-associative in pretty-print', () {
      // 2^3^2 should print without parens
      expect(
        prettyPrint(const BinaryOp(
          '^',
          NumberLit(2),
          BinaryOp('^', NumberLit(3), NumberLit(2),),
        ),),
        equals('2.0 ^ 3.0 ^ 2.0'),
      );
    });
  });
}
