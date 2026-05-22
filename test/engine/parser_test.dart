import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:test/test.dart';

void main() {
  AstNode parse(String src) => Parser(src).parseExpression();

  group('Parser literals & identifiers', () {
    test('number', () => expect(parse('42'), equals(const NumberLit(42))));
    test('identifier', () => expect(parse('K'), equals(const Identifier('K'))));
    test('parens are transparent', () {
      expect(parse('(1)'), equals(const NumberLit(1)));
    });
  });

  group('Parser arithmetic', () {
    test('addition left-associative', () {
      // a - b - c == (a - b) - c
      expect(
        parse('a - b - c'),
        equals(
          const BinaryOp(
            '-',
            BinaryOp('-', Identifier('a'), Identifier('b')),
            Identifier('c'),
          ),
        ),
      );
    });
    test('multiplication has higher precedence than addition', () {
      expect(
        parse('1 + 2 * 3'),
        equals(
          const BinaryOp(
            '+',
            NumberLit(1),
            BinaryOp('*', NumberLit(2), NumberLit(3)),
          ),
        ),
      );
    });
    test('exponent is right-associative', () {
      // 2^3^2 == 2^(3^2) == 512
      expect(
        parse('2^3^2'),
        equals(
          const BinaryOp(
            '^',
            NumberLit(2),
            BinaryOp('^', NumberLit(3), NumberLit(2)),
          ),
        ),
      );
    });
    test('unary minus binds tighter than ^ by Python/most-engineer convention', () {
      // We follow the legacy semantic: -2^2 == -(2^2) == -4
      // (Matches `pyparsing` example fourFn.py the old app used.)
      expect(
        parse('-2^2'),
        equals(const UnaryMinus(BinaryOp('^', NumberLit(2), NumberLit(2)))),
      );
    });
    test('parens override precedence', () {
      expect(
        parse('(1 + 2) * 3'),
        equals(
          const BinaryOp(
            '*',
            BinaryOp('+', NumberLit(1), NumberLit(2)),
            NumberLit(3),
          ),
        ),
      );
    });
  });

  group('Parser function calls', () {
    test('single-arg', () {
      expect(
        parse('sqrt(4)'),
        equals(const FunctionCall('sqrt', [NumberLit(4)])),
      );
    });
    test('multi-arg', () {
      expect(
        parse('min(1, 2)'),
        equals(const FunctionCall('min', [NumberLit(1), NumberLit(2)])),
      );
    });
    test('nested function call', () {
      expect(
        parse('sqrt(sin(x))'),
        equals(
          const FunctionCall('sqrt', [
            FunctionCall('sin', [Identifier('x')]),
          ]),
        ),
      );
    });
  });

  group('Parser legacy formula corpus (sanity)', () {
    test('Me formula tokenizes and parses', () {
      final ast = parse('root((2/(K-1))*((Pm/Pe)^((K-1)/K)-1))');
      expect(ast, isA<FunctionCall>());
      expect((ast as FunctionCall).name, equals('root'));
    });
    test('u(koerting) parses with E constant correctly', () {
      final ast = parse('((3.126*root((0.9825-E^(-0.3154))/(0.9694-C^(-0.57))))-3.017)');
      // Should parse without error; correctness checked by golden test later.
      expect(ast, isA<BinaryOp>());
    });
  });

  group('Parser errors', () {
    test('trailing operator', () {
      expect(() => parse('1 +'), throwsA(isA<FormatException>()));
    });
    test('unbalanced paren', () {
      expect(() => parse('(1 + 2'), throwsA(isA<FormatException>()));
    });
    test('two operands in a row', () {
      expect(() => parse('1 2'), throwsA(isA<FormatException>()));
    });
  });

  test('parseAssignment captures LHS identifier and RHS expression', () {
    final assign = Parser('Me = 2 * K').parseAssignment();
    expect(assign.lhs, equals('Me'));
    expect(assign.rhs, equals(const BinaryOp('*', NumberLit(2), Identifier('K'))));
  });
}
