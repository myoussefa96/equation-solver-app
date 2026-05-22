import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/evaluator.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:test/test.dart';

void main() {
  double eval(String src, [Map<String, double> scope = const {}]) =>
      Evaluator(scope: scope).eval(Parser(src).parseExpression());

  group('Evaluator arithmetic', () {
    test('1 + 2 == 3', () => expect(eval('1 + 2'), equals(3)));
    test('2 * 3 + 4 == 10', () => expect(eval('2 * 3 + 4'), equals(10)));
    test('2 + 3 * 4 == 14', () => expect(eval('2 + 3 * 4'), equals(14)));
    test('(2 + 3) * 4 == 20', () => expect(eval('(2 + 3) * 4'), equals(20)));
    test('2 ^ 3 ^ 2 == 512', () => expect(eval('2 ^ 3 ^ 2'), equals(512)));
    test('-2 ^ 2 == -4 (legacy convention)', () => expect(eval('-2 ^ 2'), equals(-4)));
  });

  group('Evaluator constants', () {
    test('E', () => expect(eval('E'), closeTo(2.7182818, 1e-6)));
    test('PI', () => expect(eval('PI'), closeTo(3.1415927, 1e-6)));
  });

  group('Evaluator functions', () {
    test('sqrt(16) == 4', () => expect(eval('sqrt(16)'), equals(4)));
    test('root is alias of sqrt', () => expect(eval('root(9)'), equals(3)));
    test('sin(0) == 0', () => expect(eval('sin(0)'), closeTo(0, 1e-12)));
  });

  group('Evaluator variable scope', () {
    test('reads variable from scope', () {
      expect(eval('K * 2', {'K': 1.4}), closeTo(2.8, 1e-12));
    });
    test('unknown identifier throws UnknownIdentifierError', () {
      expect(
        () => eval('Zzz + 1'),
        throwsA(isA<UnknownIdentifierError>()),
      );
    });
  });

  group('Evaluator errors', () {
    test('divide by zero', () {
      expect(() => eval('1 / 0'), throwsA(isA<EvalError>()));
    });
    test('log of zero', () {
      expect(() => eval('log(0)'), throwsA(isA<EvalError>()));
    });
    test('log of negative', () {
      expect(() => eval('log(-1)'), throwsA(isA<EvalError>()));
    });
    test('sqrt of negative', () {
      expect(() => eval('sqrt(-4)'), throwsA(isA<EvalError>()));
    });
    test('unknown function throws EvalError', () {
      expect(() => eval('bogus(1)'), throwsA(isA<EvalError>()));
    });
    test('function arity mismatch throws EvalError', () {
      expect(() => eval('sqrt(1, 2)'), throwsA(isA<EvalError>()));
    });
  });
}
