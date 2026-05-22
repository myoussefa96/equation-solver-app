import 'package:meta/meta.dart';
import 'ast.dart';
import 'dependency_resolver.dart';

@immutable
class ParsedVariable {
  const ParsedVariable({
    required this.identifier,
    required this.displayLabel,
    this.unit,
    required this.role,
    required this.isFinal,
  });

  final String identifier;
  final String displayLabel;
  final String? unit;
  final VarRole role;
  final bool isFinal;
}

@immutable
class ParsedEquation {
  const ParsedEquation({required this.outputVar, required this.ast});

  final String outputVar;     // identifier
  final AstNode ast;
}

@immutable
class ParsedEntry {
  const ParsedEntry({
    required this.name,
    this.description,
    required this.equations,
    required this.variables,
  });

  final String name;
  final String? description;
  final List<ParsedEquation> equations;
  final List<ParsedVariable> variables;
}

@immutable
class ParsedFolder {
  const ParsedFolder({required this.name, required this.entries});

  final String name;
  final List<ParsedEntry> entries;
}
