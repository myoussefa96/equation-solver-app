import 'package:meta/meta.dart';

enum TokenKind {
  number,
  identifier,
  plus,
  minus,
  star,
  slash,
  caret,
  lparen,
  rparen,
  comma,
  equals,
  eof,
}

@immutable
class Token {
  const Token(this.kind, this.lexeme, this.pos, {this.numericValue});

  final TokenKind kind;
  final String lexeme;
  final int pos;
  final double? numericValue;

  @override
  String toString() => 'Token($kind, "$lexeme", pos=$pos)';
}

class Tokenizer {
  Tokenizer(this.src);

  final String src;
  int _i = 0;

  List<Token> tokenize() {
    _i = 0;
    final out = <Token>[];
    while (_i < src.length) {
      final c = src[_i];
      if (_isWhitespace(c)) {
        _i++;
        continue;
      }
      if (_isDigit(c) || (c == '.' && _i + 1 < src.length && _isDigit(src[_i + 1]))) {
        out.add(_number());
        continue;
      }
      if (_isAlpha(c) || c == '_') {
        out.add(_identifier());
        continue;
      }
      final single = switch (c) {
        '+' => TokenKind.plus,
        '-' => TokenKind.minus,
        '*' => TokenKind.star,
        '/' => TokenKind.slash,
        '^' => TokenKind.caret,
        '(' => TokenKind.lparen,
        ')' => TokenKind.rparen,
        ',' => TokenKind.comma,
        '=' => TokenKind.equals,
        _ => null,
      };
      if (single != null) {
        out.add(Token(single, c, _i));
        _i++;
        continue;
      }
      throw FormatException('Unexpected character "$c" at position $_i', src, _i);
    }
    out.add(Token(TokenKind.eof, '', _i));
    return out;
  }

  Token _number() {
    final start = _i;
    while (_i < src.length && _isDigit(src[_i])) {
      _i++;
    }
    if (_i < src.length && src[_i] == '.') {
      _i++;
      while (_i < src.length && _isDigit(src[_i])) {
        _i++;
      }
    }
    if (_i < src.length && (src[_i] == 'e' || src[_i] == 'E')) {
      _i++;
      if (_i < src.length && (src[_i] == '+' || src[_i] == '-')) _i++;
      if (_i >= src.length || !_isDigit(src[_i])) {
        throw FormatException(
          'Malformed exponent at position $_i',
          src,
          _i,
        );
      }
      while (_i < src.length && _isDigit(src[_i])) {
        _i++;
      }
    }
    final lexeme = src.substring(start, _i);
    final value = double.parse(lexeme);
    return Token(TokenKind.number, lexeme, start, numericValue: value);
  }

  Token _identifier() {
    final start = _i;
    while (_i < src.length && (_isAlpha(src[_i]) || _isDigit(src[_i]) || src[_i] == '_')) {
      _i++;
    }
    final lexeme = src.substring(start, _i);
    return Token(TokenKind.identifier, lexeme, start);
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isAlpha(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }
  static bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
}
