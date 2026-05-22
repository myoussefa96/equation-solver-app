import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/dependency_resolver.dart';
import 'package:equation_solver_app/engine/errors.dart';
import 'package:equation_solver_app/engine/parser.dart';
import 'package:test/test.dart';

void main() {
  AstNode p(String src) => Parser(src).parseExpression();
  EqEntry eq(String lhs, String rhs) => EqEntry(output: lhs, ast: p(rhs));

  group('Topo sort + role classification', () {
    test('single equation: r = a + b', () {
      final out = DependencyResolver.resolve([eq('r', 'a + b')]);
      expect(out.order, equals(['r']));
      expect(out.roles, equals({
        'a': VarRole.input,
        'b': VarRole.input,
        'r': VarRole.output,
      }),);
    });

    test('chained: x = a + b; y = x * 2', () {
      final out = DependencyResolver.resolve([
        eq('x', 'a + b'),
        eq('y', 'x * 2'),
      ]);
      expect(out.order, equals(['x', 'y']));
      expect(out.roles['a'], equals(VarRole.input));
      expect(out.roles['b'], equals(VarRole.input));
      expect(out.roles['x'], equals(VarRole.intermediate));
      expect(out.roles['y'], equals(VarRole.output));
    });

    test('constants (E, PI) are not classified as variables', () {
      final out = DependencyResolver.resolve([eq('r', 'E * PI + a')]);
      expect(out.roles.containsKey('E'), isFalse);
      expect(out.roles.containsKey('PI'), isFalse);
      expect(out.roles['a'], equals(VarRole.input));
    });

    test('declared but unused variable is carried as input', () {
      final out = DependencyResolver.resolve(
        [eq('r', 'a + 1')],
        declaredVariables: {'a': null, 'unused': null},
      );
      expect(out.roles['unused'], equals(VarRole.input));
    });
  });

  group('Cycle detection', () {
    test('direct cycle: a = b + 1; b = a + 1', () {
      expect(
        () => DependencyResolver.resolve([
          eq('a', 'b + 1'),
          eq('b', 'a + 1'),
        ]),
        throwsA(isA<CycleError>()),
      );
    });
    test('self-loop: a = a + 1', () {
      expect(
        () => DependencyResolver.resolve([eq('a', 'a + 1')]),
        throwsA(isA<CycleError>()),
      );
    });
    test('cycle message names involved variables', () {
      try {
        DependencyResolver.resolve([
          eq('a', 'b + 1'),
          eq('b', 'a + 1'),
        ]);
        fail('expected CycleError');
      } on CycleError catch (e) {
        expect(e.cycle.toSet(), equals({'a', 'b'}));
      }
    });
  });

  group('Duplicate output detection', () {
    test('two equations assign the same LHS', () {
      expect(
        () => DependencyResolver.resolve([
          eq('a', '1'),
          eq('a', '2'),
        ]),
        throwsA(isA<EngineError>()),
      );
    });
  });
}
