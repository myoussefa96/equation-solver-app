import 'package:meta/meta.dart';
import 'ast.dart';

@immutable
sealed class EngineError implements Exception {
  const EngineError();
  String get userMessage;
}

@immutable
class ParseError extends EngineError {
  const ParseError(this.pos, this.message);

  final int pos;
  final String message;

  @override
  String get userMessage =>
      'There\'s a problem with this formula at position $pos: $message';
}

@immutable
class CycleError extends EngineError {
  const CycleError(this.cycle);

  final List<String> cycle; // ordered identifiers forming the cycle

  @override
  String get userMessage {
    final chain = cycle.join(' → ');
    return 'These formulas reference each other in a loop: $chain. '
        'Edit one of them so the loop is broken.';
  }
}

@immutable
class UnknownIdentifierError extends EngineError {
  const UnknownIdentifierError(this.name);

  final String name;

  @override
  String get userMessage =>
      'You\'re using "$name" but it isn\'t defined yet. Add it as a variable, '
      'or check the spelling.';
}

@immutable
class ReservedIdentifierError extends EngineError {
  const ReservedIdentifierError(this.name);

  final String name;

  @override
  String get userMessage =>
      '"$name" is a built-in constant or function. Pick a different name for your variable.';
}

@immutable
class EvalError extends EngineError {
  const EvalError(this.message, [this.location]);

  final String message;
  final AstNode? location;

  @override
  String get userMessage => message;
}

@immutable
class DuplicateOutputError extends EngineError {
  const DuplicateOutputError(this.name);

  final String name;

  @override
  String get userMessage =>
      'Two formulas assign "$name". Only one formula can compute each variable.';
}
