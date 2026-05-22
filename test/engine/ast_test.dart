import 'package:equation_solver_app/engine/ast.dart';
import 'package:test/test.dart';

void main() {
  group('AstNode equality', () {
    test('NumberLit equals by value', () {
      expect(const NumberLit(1.5), equals(const NumberLit(1.5)));
      expect(const NumberLit(1.5), isNot(equals(const NumberLit(1.6))));
    });

    test('Identifier equals by name', () {
      expect(const Identifier('K'), equals(const Identifier('K')));
      expect(const Identifier('K'), isNot(equals(const Identifier('Me'))));
    });

    test('UnaryMinus equals by operand', () {
      expect(
        const UnaryMinus(NumberLit(2)),
        equals(const UnaryMinus(NumberLit(2))),
      );
    });

    test('BinaryOp equals by op + children', () {
      expect(
        const BinaryOp('+', NumberLit(1), NumberLit(2)),
        equals(const BinaryOp('+', NumberLit(1), NumberLit(2))),
      );
      expect(
        const BinaryOp('+', NumberLit(1), NumberLit(2)),
        isNot(equals(const BinaryOp('-', NumberLit(1), NumberLit(2)))),
      );
    });

    test('FunctionCall equals by name + args', () {
      expect(
        const FunctionCall('sin', [NumberLit(0)]),
        equals(const FunctionCall('sin', [NumberLit(0)])),
      );
    });

    test('hashCode is consistent with equality', () {
      final a = const BinaryOp('*', Identifier('a'), Identifier('b'));
      final b = const BinaryOp('*', Identifier('a'), Identifier('b'));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
