import 'dart:math' as math;
import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:test/test.dart';

void main() {
  const tol = 1e-9;

  group('OpRegistry constants', () {
    test('PI matches math.pi', () {
      expect(OpRegistry.constants['PI'], closeTo(math.pi, tol));
    });
    test('E matches math.e', () {
      expect(OpRegistry.constants['E'], closeTo(math.e, tol));
    });
  });

  group('OpRegistry functions (basic)', () {
    test('sqrt(4) == 2', () {
      expect(OpRegistry.functions['sqrt']!.impl([4]), closeTo(2, tol));
    });
    test('root is alias of sqrt', () {
      expect(OpRegistry.functions['root']!.impl([9]), closeTo(3, tol));
    });
    test('abs(-3) == 3', () {
      expect(OpRegistry.functions['abs']!.impl([-3]), closeTo(3, tol));
    });
    test('exp(1) == E', () {
      expect(OpRegistry.functions['exp']!.impl([1]), closeTo(math.e, tol));
    });
    test('ln(E) == 1', () {
      expect(OpRegistry.functions['ln']!.impl([math.e]), closeTo(1, tol));
    });
    test('log(100) == 2 (base 10)', () {
      expect(OpRegistry.functions['log']!.impl([100]), closeTo(2, tol));
    });
    test('sin(0) == 0', () {
      expect(OpRegistry.functions['sin']!.impl([0]), closeTo(0, tol));
    });
    test('cos(0) == 1', () {
      expect(OpRegistry.functions['cos']!.impl([0]), closeTo(1, tol));
    });
    test('tan(0) == 0', () {
      expect(OpRegistry.functions['tan']!.impl([0]), closeTo(0, tol));
    });
    test('trunc(3.7) == 3.0', () {
      expect(OpRegistry.functions['trunc']!.impl([3.7]), equals(3.0));
    });
    test('round(3.6) == 4.0', () {
      expect(OpRegistry.functions['round']!.impl([3.6]), equals(4.0));
    });
    test('sgn(-5) == -1, sgn(0) == 0, sgn(7) == 1', () {
      expect(OpRegistry.functions['sgn']!.impl([-5]), equals(-1.0));
      expect(OpRegistry.functions['sgn']!.impl([0]), equals(0.0));
      expect(OpRegistry.functions['sgn']!.impl([7]), equals(1.0));
    });
  });

  group('OpRegistry helpers', () {
    test('lookup returns null for unknown', () {
      expect(OpRegistry.lookup('nonexistent'), isNull);
    });
    test('lookup returns the def for known', () {
      expect(OpRegistry.lookup('sqrt')?.name, equals('sqrt'));
    });
    test('byCategory(basic) contains sqrt and ln', () {
      final basics = OpRegistry.byCategory(OpCategory.basic).map((d) => d.name);
      expect(basics, containsAll(['sqrt', 'ln']));
    });
    test('byCategory(trig) contains sin/cos/tan', () {
      final trig = OpRegistry.byCategory(OpCategory.trig).map((d) => d.name);
      expect(trig, containsAll(['sin', 'cos', 'tan']));
    });
    test('byCategory(rounding) contains trunc and round', () {
      final round = OpRegistry.byCategory(OpCategory.rounding).map((d) => d.name);
      expect(round, containsAll(['trunc', 'round']));
    });
  });
}
