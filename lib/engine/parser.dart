import 'package:meta/meta.dart';
import 'ast.dart';
import 'tokenizer.dart';

@immutable
class Assignment {
  const Assignment(this.lhs, this.rhs);
  final String lhs;
  final AstNode rhs;
}

class Parser {
  Parser(String src) : _tokens = Tokenizer(src).tokenize();

  final List<Token> _tokens;
  int _i = 0;

  /// Parse the entire input as a single expression. Throws on trailing tokens.
  AstNode parseExpression() {
    final node = _expression(0);
    if (_peek().kind != TokenKind.eof) {
      throw FormatException(
          'Unexpected token "${_peek().lexeme}" at position ${_peek().pos}',
      );
    }
    return node;
  }

  /// Parse `IDENT '=' expression`. Throws if input doesn't match.
  Assignment parseAssignment() {
    final lhs = _consume(TokenKind.identifier, 'identifier on left of "="').lexeme;
    _consume(TokenKind.equals, '"=" between LHS and expression');
    final rhs = _expression(0);
    if (_peek().kind != TokenKind.eof) {
      throw FormatException(
          'Unexpected token "${_peek().lexeme}" at position ${_peek().pos}',
      );
    }
    return Assignment(lhs, rhs);
  }

  // ---- Pratt-style precedence climbing ----

  AstNode _expression(int minPrec) {
    AstNode lhs = _atom();
    while (true) {
      final tok = _peek();
      final op = _binaryOpFor(tok.kind);
      if (op == null) break;
      final prec = _binaryPrec[op]!;
      if (prec < minPrec) break;
      _advance();
      final rightAssoc = _rightAssoc.contains(op);
      final nextMin = rightAssoc ? prec : prec + 1;
      final rhs = _expression(nextMin);
      lhs = BinaryOp(op, lhs, rhs);
    }
    return lhs;
  }

  AstNode _atom() {
    final tok = _peek();
    switch (tok.kind) {
      case TokenKind.minus:
        _advance();
        // Legacy semantic: unary minus has lower binding than ^
        // so -2^2 == -(2^2). Achieved by consuming at caret precedence level.
        return UnaryMinus(_expression(_binaryPrec['^']!));
      case TokenKind.plus:
        _advance();
        return _atom(); // unary plus is a no-op
      case TokenKind.number:
        _advance();
        return NumberLit(tok.numericValue!);
      case TokenKind.identifier:
        _advance();
        if (_peek().kind == TokenKind.lparen) {
          _advance(); // consume (
          final args = <AstNode>[];
          if (_peek().kind != TokenKind.rparen) {
            args.add(_expression(0));
            while (_peek().kind == TokenKind.comma) {
              _advance();
              args.add(_expression(0));
            }
          }
          _consume(TokenKind.rparen, '")" after function arguments');
          return FunctionCall(tok.lexeme, args);
        }
        return Identifier(tok.lexeme);
      case TokenKind.lparen:
        _advance();
        final inner = _expression(0);
        _consume(TokenKind.rparen, '")" to close group');
        return inner;
      default:
        throw FormatException(
            'Expected number, identifier, or "(", got "${tok.lexeme}" at position ${tok.pos}',
        );
    }
  }

  static const Map<String, int> _binaryPrec = {
    '+': 1, '-': 1,
    '*': 2, '/': 2,
    '^': 3,
  };
  static const Set<String> _rightAssoc = {'^'};

  String? _binaryOpFor(TokenKind k) => switch (k) {
        TokenKind.plus => '+',
        TokenKind.minus => '-',
        TokenKind.star => '*',
        TokenKind.slash => '/',
        TokenKind.caret => '^',
        _ => null,
      };

  Token _peek() => _tokens[_i];
  Token _advance() => _tokens[_i++];

  Token _consume(TokenKind kind, String what) {
    final tok = _peek();
    if (tok.kind != kind) {
      throw FormatException('Expected $what but got "${tok.lexeme}" at position ${tok.pos}');
    }
    return _advance();
  }
}
