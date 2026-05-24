import 'package:equation_solver_app/ui/editor/chip_history.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push and undo restore prior snapshot', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    h.push(const HistorySnapshot(rows: [
      RowSnapshot(output: VarChip('y'), chips: [NumberChip('1')]),
    ]));
    expect(h.canUndo, isTrue);
    final prior = h.undo();
    expect(prior.rows, isEmpty);
    expect(h.canRedo, isTrue);
  });

  test('redo restores after undo', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    const s1 = HistorySnapshot(rows: [
      RowSnapshot(output: VarChip('y'), chips: [NumberChip('1')]),
    ]);
    h.push(s1);
    h.undo();
    final redone = h.redo();
    expect(redone, s1);
  });

  test('push after undo discards forward history', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    h.push(const HistorySnapshot(rows: []));
    h.undo();
    h.push(const HistorySnapshot(rows: [
      RowSnapshot(output: VarChip('z'), chips: []),
    ]));
    expect(h.canRedo, isFalse);
  });

  test('cap at 50 entries silently drops oldest', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    for (var i = 0; i < 60; i++) {
      h.push(HistorySnapshot(rows: [
        RowSnapshot(output: VarChip('v$i'), chips: const []),
      ]));
    }
    expect(h.size, lessThanOrEqualTo(50));
  });
}
