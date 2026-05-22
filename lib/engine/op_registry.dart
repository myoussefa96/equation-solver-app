import 'dart:math' as math;
import 'package:meta/meta.dart';

enum OpCategory {
  basic,
  trig,
  trigInverse,
  hyperbolic,
  rounding,
  combinatorics,
  more,
}

@immutable
class OpDef {
  const OpDef(this.name, this.arity, this.category, this.impl);

  final String name;
  final int arity;       // -1 = variadic
  final OpCategory category;
  final double Function(List<double>) impl;
}

double _ln10 = math.log(10);

abstract final class OpRegistry {
  static const Map<String, double> constants = {
    'PI': math.pi,
    'E': math.e,
  };

  static final Map<String, OpDef> functions = {
    'sqrt':  OpDef('sqrt',  1, OpCategory.basic,    (a) => math.sqrt(a[0])),
    'root':  OpDef('root',  1, OpCategory.basic,    (a) => math.sqrt(a[0])), // legacy alias
    'abs':   OpDef('abs',   1, OpCategory.basic,    (a) => a[0].abs()),
    'exp':   OpDef('exp',   1, OpCategory.basic,    (a) => math.exp(a[0])),
    'ln':    OpDef('ln',    1, OpCategory.basic,    (a) => math.log(a[0])),
    'log':   OpDef('log',   1, OpCategory.basic,    (a) => math.log(a[0]) / _ln10),
    'sin':   OpDef('sin',   1, OpCategory.trig,     (a) => math.sin(a[0])),
    'cos':   OpDef('cos',   1, OpCategory.trig,     (a) => math.cos(a[0])),
    'tan':   OpDef('tan',   1, OpCategory.trig,     (a) => math.tan(a[0])),
    'trunc': OpDef('trunc', 1, OpCategory.rounding, (a) => a[0].truncateToDouble()),
    'round': OpDef('round', 1, OpCategory.rounding, (a) => a[0].roundToDouble()),
    'sgn':   OpDef('sgn',   1, OpCategory.basic,    (a) => a[0].sign),
    // Scientific additions slot in here later; UI picks them up automatically.
  };

  static OpDef? lookup(String name) => functions[name];

  static List<OpDef> byCategory(OpCategory c) =>
      functions.values.where((d) => d.category == c).toList(growable: false);

  static bool isReservedIdentifier(String name) =>
      constants.containsKey(name) || functions.containsKey(name);
}
