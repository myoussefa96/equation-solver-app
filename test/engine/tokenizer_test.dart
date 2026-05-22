import 'package:equation_solver_app/engine/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  List<Token> tokenize(String src) => Tokenizer(src).tokenize();

  group('Tokenizer numbers', () {
    test('integer', () {
      final toks = tokenize('42');
      expect(toks.length, 2); // NUMBER, EOF
      expect(toks[0].kind, TokenKind.number);
      expect(toks[0].numericValue, equals(42));
    });
    test('decimal', () {
      final toks = tokenize('3.14');
      expect(toks[0].numericValue, closeTo(3.14, 1e-12));
    });
    test('leading dot', () {
      final toks = tokenize('.5');
      expect(toks[0].numericValue, closeTo(0.5, 1e-12));
    });
    test('trailing dot', () {
      final toks = tokenize('5.');
      expect(toks[0].numericValue, closeTo(5.0, 1e-12));
    });
    test('scientific notation positive exp', () {
      final toks = tokenize('1.5e3');
      expect(toks[0].numericValue, closeTo(1500.0, 1e-9));
    });
    test('scientific notation negative exp', () {
      final toks = tokenize('1e-3');
      expect(toks[0].numericValue, closeTo(0.001, 1e-15));
    });
    test('scientific notation uppercase E', () {
      final toks = tokenize('1E2');
      expect(toks[0].numericValue, closeTo(100.0, 1e-9));
    });
  });

  group('Tokenizer identifiers and constants', () {
    test('single letter identifier', () {
      final toks = tokenize('K');
      expect(toks[0].kind, TokenKind.identifier);
      expect(toks[0].lexeme, equals('K'));
    });
    test('multi-letter identifier', () {
      final toks = tokenize('Me');
      expect(toks[0].kind, TokenKind.identifier);
      expect(toks[0].lexeme, equals('Me'));
    });
    test('underscore-containing identifier', () {
      final toks = tokenize('y_t_air');
      expect(toks[0].kind, TokenKind.identifier);
      expect(toks[0].lexeme, equals('y_t_air'));
    });
    test('identifier with digits', () {
      final toks = tokenize('x1');
      expect(toks[0].kind, TokenKind.identifier);
      expect(toks[0].lexeme, equals('x1'));
    });
  });

  group('Tokenizer operators and structure', () {
    test('all five binary ops', () {
      final toks = tokenize('+ - * / ^');
      expect(
        toks.take(5).map((t) => t.kind),
        equals([TokenKind.plus, TokenKind.minus, TokenKind.star, TokenKind.slash, TokenKind.caret]),
      );
    });
    test('parens and comma', () {
      final toks = tokenize('(a, b)');
      expect(toks[0].kind, TokenKind.lparen);
      expect(toks[2].kind, TokenKind.comma);
      expect(toks[4].kind, TokenKind.rparen);
    });
    test('equals sign for legacy LHS=RHS', () {
      final toks = tokenize('x = 1');
      expect(toks[1].kind, TokenKind.equals);
    });
  });

  group('Tokenizer error cases', () {
    test('unknown character raises FormatException with position', () {
      expect(
        () => tokenize('1 @ 2'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Tokenizer whitespace handling', () {
    test('skips spaces and tabs', () {
      final toks = tokenize('  1\t+\t2  ');
      expect(
        toks.map((t) => t.kind).take(3),
        equals([TokenKind.number, TokenKind.plus, TokenKind.number]),
      );
    });
  });

  test('always emits EOF token at end', () {
    final toks = tokenize('1');
    expect(toks.last.kind, equals(TokenKind.eof));
  });
}
