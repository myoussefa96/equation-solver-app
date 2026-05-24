import 'package:equation_solver_app/engine/parser.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('flatten', () {
    test('atoms', () {
      expect(flatten([const NumberChip('12.5')]), '12.5');
      expect(flatten([const VarChip('Pm')]), 'Pm');
      expect(flatten([const ConstChip('PI')]), 'PI');
    });

    test('binary op flat sequence', () {
      expect(
        flatten([
          const NumberChip('2'),
          const OpChip('+'),
          const VarChip('x'),
        ]),
        '2 + x',
      );
    });

    test('unary minus', () {
      expect(
        flatten([const UnaryMinusChip(NumberChip('3'))]),
        '-3',
      );
    });

    test('group chip', () {
      expect(
        flatten([
          const GroupChip([
            NumberChip('1'),
            OpChip('+'),
            NumberChip('2'),
          ]),
        ]),
        '(1 + 2)',
      );
    });

    test('function chip single arg', () {
      expect(
        flatten([
          const FunctionChip('sqrt', [
            [VarChip('x')]
          ]),
        ]),
        'sqrt(x)',
      );
    });

    test('function chip multi arg', () {
      expect(
        flatten([
          const FunctionChip('root', [
            [VarChip('x')],
            [NumberChip('3')],
          ]),
        ]),
        'root(x, 3)',
      );
    });

    test('nested function inside group', () {
      expect(
        flatten([
          const GroupChip([
            FunctionChip('sqrt', [
              [VarChip('x')]
            ]),
            OpChip('+'),
            NumberChip('1'),
          ]),
        ]),
        '(sqrt(x) + 1)',
      );
    });
  });

  group('chipsFromAst round-trip', () {
    test('flatten(chipsFromAst(parse(s))) re-parses to the same AST', () {
      const examples = [
        '2 + 3',
        '(2 + 3) * 4',
        '-2^2',
        'sqrt(1 + x)',
        'sin(x) + cos(x)',
        '(a + b) / (c - d)',
        'PI * r^2',
        '-(a + b)',
      ];
      for (final s in examples) {
        final ast = Parser(s).parseExpression();
        final chips = chipsFromAst(ast);
        final flat = flatten(chips);
        final astAgain = Parser(flat).parseExpression();
        expect(astAgain.toString(), ast.toString(),
            reason: 'round-trip mismatch on: $s');
      }
    });
  });

  group('Caret + mutation helpers', () {
    test('insertAt inserts a chip at the caret', () {
      final chips = <ChipNode>[const NumberChip('1'), const OpChip('+')];
      final caret = Caret(parent: chips, index: 2);
      final newChips = insertAt(chips, caret, const NumberChip('2'));
      expect(flatten(newChips), '1 + 2');
    });

    test('backspaceAt removes chip before caret', () {
      final chips = <ChipNode>[
        const NumberChip('1'),
        const OpChip('+'),
        const NumberChip('2'),
      ];
      final caret = Caret(parent: chips, index: 3);
      final newChips = backspaceAt(chips, caret);
      expect(flatten(newChips), '1 + ');
    });

    test('backspaceAt at index 0 is a no-op', () {
      final chips = <ChipNode>[const NumberChip('1')];
      final caret = Caret(parent: chips, index: 0);
      final newChips = backspaceAt(chips, caret);
      expect(newChips, chips);
    });
  });
}
