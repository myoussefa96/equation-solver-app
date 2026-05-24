# UI Rebuild — Chip Editor Implementation Plan (Plan B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the chip-flow formula editor specced in `2026-05-24-ui-rebuild-design.md` §4-§9 — recursive ChipNode tree, container function chips, caret-based editing, variable creation flow with role+unit, progressive disclosure, multi-row with reorder/swipe, undo/redo, draft auto-save. After this plan, the user can create, edit, save, and solve real formulas via the chip editor.

**Architecture:**
- Source of truth per formula row: `List<ChipNode>` (sealed union). Container chips (GroupChip, FunctionChip) own nested child lists.
- Caret = `(parentList, index)`. Insertion mutates a copy of the chip list; state notifier rebuilds.
- Save flow: `flatten(chips) -> String -> Parser.parseExpression() -> AST -> existing storage`.
- Riverpod for editor state. SharedPreferences for advanced-toggle and drafts.

**Tech Stack:** Flutter 3.44, Dart 3.12, existing engine + storage + state.

---

## Branch

All commits on `feat/ui-rebuild` (continuation of Plan A).

## File map

**Created under `lib/ui/editor/`:**
- `chip_node.dart` — sealed ChipNode + Caret + flatten + chipsFromAst
- `chip_history.dart` — undo/redo stack
- `chip_renderer.dart` — recursive chip-list → widget renderer
- `editor_state.dart` — Riverpod state for one row: chips + caret + draft variable metadata
- `entry_editor_page.dart` — host page

**Created under `lib/ui/palette/`:**
- `palette.dart` — tab bar + content host
- `numbers_tab.dart`
- `variables_tab.dart`
- `operators_tab.dart`
- `functions_tab.dart`
- `number_sheet.dart`
- `variable_sheet.dart` — insert/swap/output modes
- `function_picker_sheet.dart`
- `op_swap_popover.dart`

**Created under `lib/ui/widgets/`:**
- `chip_widget.dart` — one ChipNode → tappable widget

**Created under `lib/state/`:**
- `editor_drafts_provider.dart` — SharedPreferences-backed draft slot

**Modified:**
- `lib/ui/entry_list_page.dart` — wire FAB + Edit menu to open the editor; deep duplicate
- `lib/storage/entries_repo.dart` — possibly add duplicate helper (or do composition in entry_list)

**Tests added under `test/engine/`:**
- `chip_node_test.dart` — flatten round-trip on 15 legacy formulas, insertion at every caret position, backspace, undo
- `chip_history_test.dart`

---

### Task 1: Chip data model (pure Dart, TDD)

**Files:**
- Create: `lib/ui/editor/chip_node.dart`
- Test: `test/engine/chip_node_test.dart`

The chip model and the flatten/parse round-trip live in `lib/ui/editor/` rather than `lib/engine/` because they're UI-facing types — but the unit test lives in `test/engine/` because it covers the engine round-trip semantics.

#### Step 1: Write failing tests

```dart
// test/engine/chip_node_test.dart
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
        flatten([UnaryMinusChip(const NumberChip('3'))]),
        '-3',
      );
    });

    test('group chip', () {
      expect(
        flatten([
          GroupChip([
            const NumberChip('1'),
            const OpChip('+'),
            const NumberChip('2'),
          ]),
        ]),
        '(1 + 2)',
      );
    });

    test('function chip single arg', () {
      expect(
        flatten([
          FunctionChip('sqrt', [
            [const VarChip('x')]
          ]),
        ]),
        'sqrt(x)',
      );
    });

    test('function chip multi arg', () {
      expect(
        flatten([
          FunctionChip('root', [
            [const VarChip('x')],
            [const NumberChip('3')],
          ]),
        ]),
        'root(x, 3)',
      );
    });

    test('nested function inside group', () {
      expect(
        flatten([
          GroupChip([
            FunctionChip('sqrt', [
              [const VarChip('x')]
            ]),
            const OpChip('+'),
            const NumberChip('1'),
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
        expect(astAgain.toString(), ast.toString(), reason: 'round-trip mismatch on: $s');
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
```

#### Step 2: Run, see failures

`flutter test test/engine/chip_node_test.dart`
Expected: FAIL — types not found.

#### Step 3: Implement `chip_node.dart`

```dart
// lib/ui/editor/chip_node.dart
import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/op_registry.dart';

sealed class ChipNode {
  const ChipNode();
}

class NumberChip extends ChipNode {
  const NumberChip(this.text);
  final String text;
  @override
  String toString() => 'NumberChip($text)';
  @override
  bool operator ==(Object o) => o is NumberChip && o.text == text;
  @override
  int get hashCode => text.hashCode;
}

class VarChip extends ChipNode {
  const VarChip(this.name);
  final String name;
  @override
  String toString() => 'VarChip($name)';
  @override
  bool operator ==(Object o) => o is VarChip && o.name == name;
  @override
  int get hashCode => name.hashCode;
}

class ConstChip extends ChipNode {
  const ConstChip(this.name);
  final String name;
  @override
  String toString() => 'ConstChip($name)';
  @override
  bool operator ==(Object o) => o is ConstChip && o.name == name;
  @override
  int get hashCode => name.hashCode;
}

class OpChip extends ChipNode {
  const OpChip(this.op);
  final String op;
  @override
  String toString() => 'OpChip($op)';
  @override
  bool operator ==(Object o) => o is OpChip && o.op == op;
  @override
  int get hashCode => op.hashCode;
}

class UnaryMinusChip extends ChipNode {
  const UnaryMinusChip(this.operand);
  final ChipNode operand;
  @override
  String toString() => 'UnaryMinusChip($operand)';
  @override
  bool operator ==(Object o) => o is UnaryMinusChip && o.operand == operand;
  @override
  int get hashCode => operand.hashCode;
}

class GroupChip extends ChipNode {
  const GroupChip(this.children);
  final List<ChipNode> children;
  @override
  String toString() => 'GroupChip($children)';
  @override
  bool operator ==(Object o) =>
      o is GroupChip && _listEq(o.children, children);
  @override
  int get hashCode => Object.hashAll(children);
}

class FunctionChip extends ChipNode {
  const FunctionChip(this.name, this.args);
  final String name;
  final List<List<ChipNode>> args;
  @override
  String toString() => 'FunctionChip($name, $args)';
  @override
  bool operator ==(Object o) {
    if (o is! FunctionChip || o.name != name || o.args.length != args.length) {
      return false;
    }
    for (var i = 0; i < args.length; i++) {
      if (!_listEq(o.args[i], args[i])) return false;
    }
    return true;
  }
  @override
  int get hashCode => Object.hash(name, Object.hashAll(args.map(Object.hashAll)));
}

bool _listEq(List<ChipNode> a, List<ChipNode> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Caret
// ---------------------------------------------------------------------------

class Caret {
  Caret({required this.parent, required this.index});
  final List<ChipNode> parent;
  final int index;
}

// ---------------------------------------------------------------------------
// flatten — chip tree -> parser-ready string
// ---------------------------------------------------------------------------

String flatten(List<ChipNode> chips) {
  final buf = StringBuffer();
  for (final c in chips) {
    buf.write(_flattenOne(c));
  }
  return buf.toString();
}

String _flattenOne(ChipNode c) {
  return switch (c) {
    NumberChip(:final text) => text,
    VarChip(:final name) => name,
    ConstChip(:final name) => name,
    OpChip(:final op) => ' $op ',
    UnaryMinusChip(:final operand) => '-${_flattenOne(operand)}',
    GroupChip(:final children) => '(${flatten(children)})',
    FunctionChip(:final name, :final args) =>
      '$name(${args.map(flatten).join(', ')})',
  };
}

// ---------------------------------------------------------------------------
// chipsFromAst — AST -> chip tree (for loading existing formulas)
// ---------------------------------------------------------------------------

/// Convert an AST node into a sequence of sibling chips at the *parent's
/// level*. BinaryOp expands to flat siblings; everything else returns a
/// single-element list.
List<ChipNode> chipsFromAst(AstNode n) {
  return switch (n) {
    NumberLit(:final value) => [NumberChip(_formatNumber(value))],
    Identifier(:final name) when OpRegistry.constants.containsKey(name) => [
        ConstChip(name)
      ],
    Identifier(:final name) => [VarChip(name)],
    UnaryMinus(:final operand) => [UnaryMinusChip(_asAtom(operand))],
    BinaryOp(:final left, :final op, :final right) => [
        ..._wrapForBinarySide(left),
        OpChip(op),
        ..._wrapForBinarySide(right),
      ],
    FunctionCall(:final name, :final args) => [
        FunctionChip(name, args.map(chipsFromAst).toList()),
      ],
  };
}

String _formatNumber(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

ChipNode _asAtom(AstNode n) {
  final list = chipsFromAst(n);
  if (list.length == 1) return list[0];
  return GroupChip(list);
}

List<ChipNode> _wrapForBinarySide(AstNode n) {
  // Wrap nested binary ops in a GroupChip so the rendered chip tree shows the
  // explicit grouping. Atoms (numbers, vars, function calls) stay un-wrapped.
  return switch (n) {
    BinaryOp() => [GroupChip(chipsFromAst(n))],
    _ => chipsFromAst(n),
  };
}

// ---------------------------------------------------------------------------
// Mutation helpers
// ---------------------------------------------------------------------------

List<ChipNode> insertAt(List<ChipNode> list, Caret caret, ChipNode chip) {
  // Only handles caret in the top-level list. For nested carets, the editor
  // state holds a path; this helper is the building block.
  final copy = List<ChipNode>.from(list);
  copy.insert(caret.index, chip);
  return copy;
}

List<ChipNode> backspaceAt(List<ChipNode> list, Caret caret) {
  if (caret.index == 0) return list;
  final copy = List<ChipNode>.from(list);
  copy.removeAt(caret.index - 1);
  return copy;
}
```

#### Step 4: Run, see pass

`flutter test test/engine/chip_node_test.dart`
Expected: all green.

#### Step 5: Commit

```bash
git add lib/ui/editor/chip_node.dart test/engine/chip_node_test.dart
git commit -m "feat(editor): ChipNode model + flatten + chipsFromAst + caret helpers"
```

---

### Task 2: Editor state notifier (per-row chip tree + caret + history)

**Files:**
- Create: `lib/ui/editor/editor_state.dart`
- Create: `lib/ui/editor/chip_history.dart`
- Test: `test/engine/chip_history_test.dart`

This task introduces the per-row state container that the editor page mutates. Each row holds: its chip tree, its caret, an output VarChip (or null), and pending variable metadata for new vars created in this session.

History is per-entry (not per-row) so cross-row operations (add/delete/reorder) are undoable.

#### Step 1: ChipHistory test

```dart
// test/engine/chip_history_test.dart
import 'package:equation_solver_app/ui/editor/chip_history.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push and undo restore prior snapshot', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    h.push(HistorySnapshot(rows: [
      RowSnapshot(output: const VarChip('y'), chips: const [NumberChip('1')]),
    ]));
    expect(h.canUndo, isTrue);
    final prior = h.undo();
    expect(prior.rows, isEmpty);
    expect(h.canRedo, isTrue);
  });

  test('redo restores after undo', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    final s1 = HistorySnapshot(rows: [
      RowSnapshot(output: const VarChip('y'), chips: const [NumberChip('1')]),
    ]);
    h.push(s1);
    h.undo();
    final redone = h.redo();
    expect(redone, s1);
  });

  test('push after undo discards forward history', () {
    final h = ChipHistory(initial: const HistorySnapshot(rows: []));
    h.push(HistorySnapshot(rows: const []));
    h.undo();
    h.push(HistorySnapshot(rows: const []));
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
```

#### Step 2: Run, see fail

`flutter test test/engine/chip_history_test.dart`
Expected: FAIL — types not found.

#### Step 3: Implement chip_history.dart

```dart
// lib/ui/editor/chip_history.dart
import 'package:equation_solver_app/ui/editor/chip_node.dart';

class RowSnapshot {
  const RowSnapshot({
    required this.output,
    required this.chips,
  });
  final VarChip? output;
  final List<ChipNode> chips;

  @override
  bool operator ==(Object o) =>
      o is RowSnapshot &&
      o.output == output &&
      o.chips.length == chips.length &&
      _listEq(o.chips, chips);

  @override
  int get hashCode => Object.hash(output, Object.hashAll(chips));

  static bool _listEq(List<ChipNode> a, List<ChipNode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class HistorySnapshot {
  const HistorySnapshot({required this.rows});
  final List<RowSnapshot> rows;

  @override
  bool operator ==(Object o) =>
      o is HistorySnapshot &&
      o.rows.length == rows.length &&
      List.generate(rows.length, (i) => o.rows[i] == rows[i]).every((x) => x);

  @override
  int get hashCode => Object.hashAll(rows);
}

class ChipHistory {
  ChipHistory({required HistorySnapshot initial}) : _current = initial;

  HistorySnapshot _current;
  final List<HistorySnapshot> _undo = [];
  final List<HistorySnapshot> _redo = [];
  static const int _cap = 50;

  HistorySnapshot get current => _current;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get size => _undo.length + _redo.length;

  void push(HistorySnapshot next) {
    if (next == _current) return;
    _undo.add(_current);
    if (_undo.length > _cap) _undo.removeAt(0);
    _current = next;
    _redo.clear();
  }

  HistorySnapshot undo() {
    if (!canUndo) return _current;
    _redo.add(_current);
    _current = _undo.removeLast();
    return _current;
  }

  HistorySnapshot redo() {
    if (!canRedo) return _current;
    _undo.add(_current);
    if (_undo.length > _cap) _undo.removeAt(0);
    _current = _redo.removeLast();
    return _current;
  }
}
```

#### Step 4: editor_state.dart

```dart
// lib/ui/editor/editor_state.dart
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/chip_history.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter/foundation.dart';

/// Identity reference for a chip-list location: which list, which index.
/// Equality is by identity of `parent` (not by content).
class CaretPath {
  CaretPath({required this.parent, required this.index});
  final List<ChipNode> parent;
  final int index;
}

/// Pending variable metadata that hasn't been persisted yet.
class DraftVarMeta {
  const DraftVarMeta({
    required this.identifier,
    required this.displayLabel,
    required this.unit,
    required this.role,
  });
  final String identifier;
  final String displayLabel;
  final String? unit;
  final VarRole role;
}

class EditorRow {
  EditorRow({
    this.output,
    List<ChipNode>? chips,
  }) : chips = chips ?? [];

  VarChip? output;
  List<ChipNode> chips;
  CaretPath? caret;
  String? rowError;
}

class EditorState extends ChangeNotifier {
  EditorState({
    required this.entryId,
    required this.folderId,
    required this.entryName,
    String? entryDescription,
    List<EditorRow>? initialRows,
  })  : _name = entryName,
        _description = entryDescription,
        rows = initialRows ?? [EditorRow()] {
    history = ChipHistory(initial: _snapshot());
  }

  final int? entryId;
  final int folderId;
  String _name;
  String? _description;
  final List<EditorRow> rows;
  late ChipHistory history;

  // Variable metadata pending persistence (created via the variable sheet but
  // not yet committed to the DB).
  final Map<String, DraftVarMeta> draftVarMeta = {};

  int activeRowIndex = 0;
  String? bannerError;

  String get name => _name;
  set name(String v) {
    _name = v;
    notifyListeners();
  }

  String? get description => _description;
  set description(String? v) {
    _description = v;
    notifyListeners();
  }

  EditorRow get active => rows[activeRowIndex.clamp(0, rows.length - 1)];

  void setActiveRow(int i) {
    activeRowIndex = i.clamp(0, rows.length - 1);
    notifyListeners();
  }

  HistorySnapshot _snapshot() => HistorySnapshot(
        rows: rows
            .map((r) => RowSnapshot(output: r.output, chips: List.from(r.chips)))
            .toList(),
      );

  /// Take a snapshot of current state and push to history. Called after every
  /// logical operation.
  void pushHistory() {
    history.push(_snapshot());
  }

  void undo() {
    if (!history.canUndo) return;
    final snap = history.undo();
    _restore(snap);
  }

  void redo() {
    if (!history.canRedo) return;
    final snap = history.redo();
    _restore(snap);
  }

  void _restore(HistorySnapshot snap) {
    rows
      ..clear()
      ..addAll(snap.rows.map((s) => EditorRow(
            output: s.output,
            chips: List.from(s.chips),
          )));
    if (rows.isEmpty) rows.add(EditorRow());
    activeRowIndex = activeRowIndex.clamp(0, rows.length - 1);
    notifyListeners();
  }

  void addRow() {
    rows.add(EditorRow());
    activeRowIndex = rows.length - 1;
    pushHistory();
    notifyListeners();
  }

  void deleteRow(int index) {
    if (rows.length <= 1) return;
    rows.removeAt(index);
    if (activeRowIndex >= rows.length) activeRowIndex = rows.length - 1;
    pushHistory();
    notifyListeners();
  }

  void reorderRow(int from, int to) {
    if (from == to) return;
    final r = rows.removeAt(from);
    rows.insert(to > from ? to - 1 : to, r);
    pushHistory();
    notifyListeners();
  }

  /// Insert [chip] at the current caret position in the active row.
  void insertAtCaret(ChipNode chip) {
    final row = active;
    final caret = row.caret ?? CaretPath(parent: row.chips, index: row.chips.length);
    final list = caret.parent;
    list.insert(caret.index.clamp(0, list.length), chip);
    row.caret = CaretPath(parent: list, index: caret.index + 1);
    pushHistory();
    notifyListeners();
  }

  /// Insert a function chip and place caret inside arg[0].
  void insertFunction(String name, {int arity = 1}) {
    final fn = FunctionChip(name, List.generate(arity, (_) => <ChipNode>[]));
    insertAtCaret(fn);
    final row = active;
    row.caret = CaretPath(parent: fn.args[0], index: 0);
    notifyListeners();
  }

  void insertGroup() {
    final g = GroupChip(<ChipNode>[]);
    insertAtCaret(g);
    final row = active;
    row.caret = CaretPath(parent: g.children, index: 0);
    notifyListeners();
  }

  /// Move caret out of current group/function arg.
  void closeContainer() {
    final row = active;
    // No-op fallback: place caret at end of top-level row.
    row.caret = CaretPath(parent: row.chips, index: row.chips.length);
    notifyListeners();
  }

  /// Backspace at the caret.
  void backspace() {
    final row = active;
    final caret = row.caret;
    if (caret == null || caret.index == 0) return;
    caret.parent.removeAt(caret.index - 1);
    row.caret = CaretPath(parent: caret.parent, index: caret.index - 1);
    pushHistory();
    notifyListeners();
  }

  /// Replace the chip at [path] with [replacement]. Used by tap-to-edit on
  /// number/var/op chips.
  void replaceChip(CaretPath path, ChipNode replacement) {
    final list = path.parent;
    if (path.index < 0 || path.index >= list.length) return;
    list[path.index] = replacement;
    pushHistory();
    notifyListeners();
  }

  /// Delete the chip at [path]. Used by long-press menus.
  void deleteChip(CaretPath path) {
    final list = path.parent;
    if (path.index < 0 || path.index >= list.length) return;
    list.removeAt(path.index);
    final row = active;
    row.caret = CaretPath(parent: list, index: path.index.clamp(0, list.length));
    pushHistory();
    notifyListeners();
  }

  /// Set the row's output chip.
  void setOutput(int rowIndex, VarChip v) {
    rows[rowIndex].output = v;
    pushHistory();
    notifyListeners();
  }
}
```

#### Step 5: Run

`flutter test test/engine/chip_history_test.dart`
Expected: 4/4 pass.

#### Step 6: Commit

```bash
git add lib/ui/editor/chip_history.dart lib/ui/editor/editor_state.dart test/engine/chip_history_test.dart
git commit -m "feat(editor): EditorState (rows, caret, history) + ChipHistory undo/redo"
```

---

### Task 3: ChipWidget + ChipRenderer (rendering layer)

**Files:**
- Create: `lib/ui/widgets/chip_widget.dart`
- Create: `lib/ui/editor/chip_renderer.dart`

ChipWidget renders one ChipNode as a tappable widget. ChipRenderer walks a List<ChipNode> producing a horizontally-scrolling row of ChipWidgets with caret indicators between them.

For now, tap handlers can be `VoidCallback?` — wiring to sheets/popovers comes in Tasks 5-7. Color coding for VarChip is parameterized via a `varRole` lookup.

```dart
// lib/ui/widgets/chip_widget.dart
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter/material.dart';

typedef VarRoleLookup = VarRole? Function(String identifier);

class ChipWidget extends StatelessWidget {
  const ChipWidget({
    super.key,
    required this.chip,
    required this.onTap,
    required this.onLongPress,
    required this.roleOf,
    required this.childRenderer,
  });

  final ChipNode chip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VarRoleLookup roleOf;
  final Widget Function(List<ChipNode> children) childRenderer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (chip) {
      NumberChip(:final text) => _basic(context, text, scheme.surface, scheme.onSurface),
      VarChip(:final name) => _varPill(context, name, scheme),
      ConstChip(:final name) => _basic(context, _renderConstName(name), scheme.surfaceContainerHighest, scheme.onSurface),
      OpChip(:final op) => _basic(context, _renderOp(op), scheme.surface, scheme.primary, weight: FontWeight.bold),
      UnaryMinusChip(:final operand) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _basic(context, '−', scheme.surface, scheme.primary, weight: FontWeight.bold),
            ChipWidget(
              chip: operand,
              onTap: onTap,
              onLongPress: onLongPress,
              roleOf: roleOf,
              childRenderer: childRenderer,
            ),
          ],
        ),
      GroupChip(:final children) => _container(context, '(', ')', childRenderer(children)),
      FunctionChip(:final name, :final args) => _function(context, name, args),
    };
  }

  Widget _basic(
    BuildContext context,
    String label,
    Color bg,
    Color fg, {
    FontWeight weight = FontWeight.w500,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: weight,
            color: fg,
          ),
        ),
      ),
    );
  }

  Widget _varPill(BuildContext context, String name, ColorScheme scheme) {
    final role = roleOf(name);
    final (bg, fg) = switch (role) {
      VarRole.input => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      VarRole.output => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      null => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return _basic(context, name, bg, fg);
  }

  Widget _container(BuildContext context, String open, String close, Widget body) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(open, style: TextStyle(fontFamily: 'monospace', fontSize: 22, color: scheme.outline)),
        body,
        Text(close, style: TextStyle(fontFamily: 'monospace', fontSize: 22, color: scheme.outline)),
      ],
    );
  }

  Widget _function(BuildContext context, String name, List<List<ChipNode>> args) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(left: 1, right: 0, top: 2, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              _renderFnName(name),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
              right: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < args.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(',',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            color: scheme.outline)),
                  ),
                childRenderer(args[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _renderOp(String op) => switch (op) {
        '*' => '×',
        '/' => '÷',
        '-' => '−',
        _ => op,
      };

  static String _renderConstName(String name) => switch (name) {
        'PI' => 'π',
        'E' => 'e',
        _ => name,
      };

  static String _renderFnName(String name) => switch (name) {
        'sqrt' => '√',
        _ => name,
      };
}
```

```dart
// lib/ui/editor/chip_renderer.dart
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:equation_solver_app/ui/editor/editor_state.dart';
import 'package:equation_solver_app/ui/widgets/chip_widget.dart';
import 'package:flutter/material.dart';

class ChipRenderer extends StatelessWidget {
  const ChipRenderer({
    super.key,
    required this.chips,
    required this.caret,
    required this.onCaretTap,
    required this.onChipTap,
    required this.onChipLongPress,
    required this.roleOf,
  });

  final List<ChipNode> chips;
  final CaretPath? caret;

  /// Tap at a gap between chips → set caret here.
  final void Function(List<ChipNode> parent, int index) onCaretTap;

  /// Tap a chip → handle per-type action.
  final void Function(List<ChipNode> parent, int index, ChipNode chip)
      onChipTap;

  /// Long-press a chip → handle delete etc.
  final void Function(List<ChipNode> parent, int index, ChipNode chip)
      onChipLongPress;

  final VarRoleLookup roleOf;

  @override
  Widget build(BuildContext context) {
    return _renderList(context, chips);
  }

  Widget _renderList(BuildContext context, List<ChipNode> list) {
    final items = <Widget>[];
    for (var i = 0; i <= list.length; i++) {
      items.add(_gap(context, list, i));
      if (i < list.length) {
        items.add(ChipWidget(
          chip: list[i],
          onTap: () => onChipTap(list, i, list[i]),
          onLongPress: () => onChipLongPress(list, i, list[i]),
          roleOf: roleOf,
          childRenderer: (children) => _renderList(context, children),
        ));
      }
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  Widget _gap(BuildContext context, List<ChipNode> parent, int index) {
    final showCaret = caret != null &&
        identical(caret!.parent, parent) &&
        caret!.index == index;
    return GestureDetector(
      onTap: () => onCaretTap(parent, index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 6,
        height: 36,
        child: showCaret
            ? Center(
                child: Container(
                  width: 2,
                  height: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : null,
      ),
    );
  }
}
```

#### Commit

```bash
git add lib/ui/widgets/chip_widget.dart lib/ui/editor/chip_renderer.dart
git commit -m "feat(editor): ChipWidget + ChipRenderer with caret gaps + color coding"
```

---

### Task 4: Sheets — number, variable, function picker, op swap

**Files:**
- Create: `lib/ui/palette/number_sheet.dart`
- Create: `lib/ui/palette/variable_sheet.dart`
- Create: `lib/ui/palette/function_picker_sheet.dart`
- Create: `lib/ui/palette/op_swap_popover.dart`

#### number_sheet.dart

```dart
// lib/ui/palette/number_sheet.dart
import 'package:flutter/material.dart';

/// Modal bottom sheet for editing a number atomically. Returns the new
/// text string, or null if cancelled.
Future<String?> showNumberSheet(
  BuildContext context, {
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit number',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. 1.4 or 2.5e-3',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('OK'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
```

#### op_swap_popover.dart

```dart
// lib/ui/palette/op_swap_popover.dart
import 'package:flutter/material.dart';

/// Shows a popover near [position] with the other 4 operators (skips [current]).
Future<String?> showOpSwapPopover(
  BuildContext context, {
  required String current,
  required RelativeRect position,
}) {
  const ops = ['+', '-', '*', '/', '^'];
  final others = ops.where((o) => o != current).toList();
  return showMenu<String>(
    context: context,
    position: position,
    items: [
      for (final o in others)
        PopupMenuItem<String>(
          value: o,
          child: Text(
            _display(o),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
    ],
  );
}

String _display(String op) => switch (op) {
      '*' => '×',
      '/' => '÷',
      '-' => '−',
      _ => op,
    };
```

#### function_picker_sheet.dart

```dart
// lib/ui/palette/function_picker_sheet.dart
import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:flutter/material.dart';

class FunctionPick {
  const FunctionPick(this.name, this.arity);
  final String name;
  final int arity;
}

Future<FunctionPick?> showFunctionPickerSheet(
  BuildContext context, {
  required bool advancedEnabled,
}) {
  return showModalBottomSheet<FunctionPick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _FunctionPickerBody(advancedEnabled: advancedEnabled),
  );
}

class _FunctionPickerBody extends StatefulWidget {
  const _FunctionPickerBody({required this.advancedEnabled});
  final bool advancedEnabled;

  @override
  State<_FunctionPickerBody> createState() => _FunctionPickerBodyState();
}

class _FunctionPickerBodyState extends State<_FunctionPickerBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entries = OpRegistry.functions.entries.where((e) {
      final cat = e.value.category;
      if (!widget.advancedEnabled && cat != OpCategory.basic) return false;
      if (_query.isEmpty) return true;
      return e.key.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search functions',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i];
                return ListTile(
                  title: Text(e.key,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(_describe(e.value.category)),
                  onTap: () => Navigator.of(ctx).pop(
                      FunctionPick(e.key, e.value.arity)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _describe(OpCategory c) => switch (c) {
        OpCategory.basic => 'Basic',
        OpCategory.trigInverse => 'Inverse trigonometry',
        OpCategory.hyperbolic => 'Hyperbolic',
        OpCategory.rounding => 'Rounding',
        OpCategory.more => 'More',
      };
}
```

> **Note:** `OpDef` in `lib/engine/op_registry.dart` may not currently expose `arity`. If absent, add a `final int arity;` field with default 1, set explicitly for `root` (arity 2). Implementer should verify and patch.

#### variable_sheet.dart

```dart
// lib/ui/palette/variable_sheet.dart
import 'package:equation_solver_app/engine/op_registry.dart';
import 'package:equation_solver_app/engine/slugify.dart';
import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/editor_state.dart';
import 'package:flutter/material.dart';

enum VariableSheetMode { insert, swap, output }

class VariableSheetResult {
  const VariableSheetResult.existing(this.identifier) : created = null;
  const VariableSheetResult.created(this.created) : identifier = created!.identifier;

  final String identifier;
  final DraftVarMeta? created;
}

class VariableEntry {
  const VariableEntry(this.identifier, this.label, this.unit, this.role);
  final String identifier;
  final String label;
  final String? unit;
  final VarRole role;
}

Future<VariableSheetResult?> showVariableSheet(
  BuildContext context, {
  required VariableSheetMode mode,
  required List<VariableEntry> existingVars,
  required Set<String> reservedIdentifiers,
}) {
  return showModalBottomSheet<VariableSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _VariableSheetBody(
      mode: mode,
      existingVars: existingVars,
      reservedIdentifiers: reservedIdentifiers,
    ),
  );
}

class _VariableSheetBody extends StatelessWidget {
  const _VariableSheetBody({
    required this.mode,
    required this.existingVars,
    required this.reservedIdentifiers,
  });

  final VariableSheetMode mode;
  final List<VariableEntry> existingVars;
  final Set<String> reservedIdentifiers;

  @override
  Widget build(BuildContext context) {
    final inputs = existingVars.where((v) => v.role == VarRole.input).toList();
    final outputs = existingVars.where((v) => v.role == VarRole.output).toList();
    final constants = OpRegistry.constants.keys.toList();

    final title = mode == VariableSheetMode.output
        ? 'What does this formula compute?'
        : (mode == VariableSheetMode.swap ? 'Swap variable' : 'Pick a variable');

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title,
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                if (mode != VariableSheetMode.output) ...[
                  _section(ctx, 'You enter'),
                  if (inputs.isEmpty)
                    _placeholder(ctx, '(none yet — create one)')
                  else
                    for (final v in inputs)
                      _row(ctx, v, () => Navigator.of(ctx).pop(VariableSheetResult.existing(v.identifier))),
                  _section(ctx, 'Computed from earlier formulas'),
                  if (outputs.isEmpty)
                    _placeholder(ctx, '(none yet — earlier formulas will appear here)')
                  else
                    for (final v in outputs)
                      _row(ctx, v, () => Navigator.of(ctx).pop(VariableSheetResult.existing(v.identifier))),
                  _section(ctx, 'Constants'),
                  for (final name in constants)
                    ListTile(
                      title: Text(name,
                          style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(OpRegistry.constants[name]!.toString()),
                      onTap: () => Navigator.of(ctx).pop(VariableSheetResult.existing(name)),
                    ),
                ] else ...[
                  // Output mode: only show outputs (computed) without a current source.
                  _section(ctx, 'Pick a variable already used in this entry'),
                  if (outputs.isEmpty)
                    _placeholder(ctx, '(no orphan variables)')
                  else
                    for (final v in outputs)
                      _row(ctx, v, () => Navigator.of(ctx).pop(VariableSheetResult.existing(v.identifier))),
                ],
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(mode == VariableSheetMode.output
                        ? 'New computed variable…'
                        : 'New variable…'),
                    onPressed: () async {
                      final created = await _showCreateVariableForm(
                        ctx,
                        existingIdentifiers: {
                          ...existingVars.map((v) => v.identifier),
                          ...reservedIdentifiers,
                        },
                        forcedRole: mode == VariableSheetMode.output
                            ? VarRole.output
                            : null,
                      );
                      if (created != null && ctx.mounted) {
                        Navigator.of(ctx).pop(VariableSheetResult.created(created));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext ctx, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
      );

  Widget _placeholder(BuildContext ctx, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
      );

  Widget _row(BuildContext ctx, VariableEntry v, VoidCallback onTap) {
    final scheme = Theme.of(ctx).colorScheme;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: v.role == VarRole.input
                  ? scheme.tertiaryContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(v.identifier,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v.label)),
          if (v.unit != null)
            Text('[${v.unit}]',
                style: TextStyle(color: scheme.outline)),
        ],
      ),
    );
  }
}

Future<DraftVarMeta?> _showCreateVariableForm(
  BuildContext context, {
  required Set<String> existingIdentifiers,
  required VarRole? forcedRole,
}) async {
  final nameCtrl = TextEditingController();
  final unitCtrl = TextEditingController();
  VarRole? role = forcedRole;
  String? nameError;

  return showDialog<DraftVarMeta>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add a variable'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Pm or rho',
                  errorText: nameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "We'll use this name everywhere you see it.",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  hintText: 'e.g. kg/m³',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Role',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<VarRole>(
                title: const Text("I'll type this in"),
                subtitle: const Text('(like Pm, Pe, K…)'),
                value: VarRole.input,
                groupValue: role,
                onChanged: forcedRole != null
                    ? null
                    : (v) => setState(() => role = v),
              ),
              RadioListTile<VarRole>(
                title: const Text('The app calculates it from another formula'),
                value: VarRole.output,
                groupValue: role,
                onChanged: forcedRole != null
                    ? null
                    : (v) => setState(() => role = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: role == null
                ? null
                : () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setState(() => nameError = 'Required');
                      return;
                    }
                    final identifier = slugify(name);
                    if (OpRegistry.isReservedIdentifier(identifier)) {
                      setState(() => nameError =
                          'This name is reserved — try a different one.');
                      return;
                    }
                    if (existingIdentifiers.contains(identifier)) {
                      setState(() => nameError =
                          'Already used by another variable — pick a different name.');
                      return;
                    }
                    Navigator.of(ctx).pop(DraftVarMeta(
                      identifier: identifier,
                      displayLabel: name,
                      unit: unitCtrl.text.trim().isEmpty
                          ? null
                          : unitCtrl.text.trim(),
                      role: role!,
                    ));
                  },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
```

#### Commit

```bash
git add lib/ui/palette/number_sheet.dart lib/ui/palette/op_swap_popover.dart lib/ui/palette/function_picker_sheet.dart lib/ui/palette/variable_sheet.dart
git commit -m "feat(palette): number sheet + op swap + function picker + variable sheet (3 modes)"
```

---

### Task 5: Palette tabs (numbers / vars / operators / functions)

**Files:**
- Create: `lib/ui/palette/palette.dart`
- Create: `lib/ui/palette/numbers_tab.dart`
- Create: `lib/ui/palette/variables_tab.dart`
- Create: `lib/ui/palette/operators_tab.dart`
- Create: `lib/ui/palette/functions_tab.dart`

The palette is the bottom bar with 4 tabs. Each tab dispatches actions via callbacks. Caret-aware glow is implemented via an `isOperatorContext` boolean derived from the chip immediately before the caret.

```dart
// lib/ui/palette/palette.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equation_solver_app/state/settings_provider.dart';

import 'numbers_tab.dart';
import 'variables_tab.dart';
import 'operators_tab.dart';
import 'functions_tab.dart';

typedef ChipCallback = void Function(String);

class Palette extends ConsumerStatefulWidget {
  const Palette({
    super.key,
    required this.activeRowLabel,
    required this.isOperatorContext,
    required this.existingVarChips,
    required this.onAppendDigit,
    required this.onToggleSign,
    required this.onScientificE,
    required this.onOpenGroup,
    required this.onCloseGroup,
    required this.onBackspace,
    required this.onPickVariable,
    required this.onNewVariable,
    required this.onInsertVarChip,
    required this.onOperator,
    required this.onFunction,
  });

  final String activeRowLabel;
  final bool isOperatorContext;
  final List<({String identifier, bool isInput})> existingVarChips;

  final ChipCallback onAppendDigit;
  final VoidCallback onToggleSign;
  final VoidCallback onScientificE;
  final VoidCallback onOpenGroup;
  final VoidCallback onCloseGroup;
  final VoidCallback onBackspace;

  final VoidCallback onPickVariable;
  final VoidCallback onNewVariable;
  final ChipCallback onInsertVarChip;

  final ChipCallback onOperator;
  final VoidCallback onFunction;

  @override
  ConsumerState<Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<Palette>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _labels = ['123', 'Vars', '±×÷', 'fn'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _labels.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context),
          TabBar(
            controller: _tab,
            tabs: [for (final l in _labels) Tab(text: l)],
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: _tab,
              children: [
                NumbersTab(
                  onAppendDigit: widget.onAppendDigit,
                  onToggleSign: widget.onToggleSign,
                  onScientificE: widget.onScientificE,
                  onOpenGroup: widget.onOpenGroup,
                  onCloseGroup: widget.onCloseGroup,
                  onBackspace: widget.onBackspace,
                ),
                VariablesTab(
                  existing: widget.existingVarChips,
                  onPick: widget.onInsertVarChip,
                  onNew: widget.onNewVariable,
                ),
                OperatorsTab(
                  isOperatorContext: widget.isOperatorContext,
                  onOperator: widget.onOperator,
                  onOpenGroup: widget.onOpenGroup,
                  onCloseGroup: widget.onCloseGroup,
                ),
                FunctionsTab(onPick: widget.onFunction),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.edit, size: 14, color: scheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Editing: ${widget.activeRowLabel}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.backspace_outlined),
            iconSize: 20,
            onPressed: widget.onBackspace,
            tooltip: 'Backspace',
          ),
        ],
      ),
    );
  }
}
```

```dart
// lib/ui/palette/numbers_tab.dart
import 'package:flutter/material.dart';

class NumbersTab extends StatelessWidget {
  const NumbersTab({
    super.key,
    required this.onAppendDigit,
    required this.onToggleSign,
    required this.onScientificE,
    required this.onOpenGroup,
    required this.onCloseGroup,
    required this.onBackspace,
  });

  final void Function(String) onAppendDigit;
  final VoidCallback onToggleSign;
  final VoidCallback onScientificE;
  final VoidCallback onOpenGroup;
  final VoidCallback onCloseGroup;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final buttons = <(String, VoidCallback)>[
      ('7', () => onAppendDigit('7')),
      ('8', () => onAppendDigit('8')),
      ('9', () => onAppendDigit('9')),
      ('.', () => onAppendDigit('.')),
      ('4', () => onAppendDigit('4')),
      ('5', () => onAppendDigit('5')),
      ('6', () => onAppendDigit('6')),
      ('±', onToggleSign),
      ('1', () => onAppendDigit('1')),
      ('2', () => onAppendDigit('2')),
      ('3', () => onAppendDigit('3')),
      ('(', onOpenGroup),
      ('0', () => onAppendDigit('0')),
      ('⌫', onBackspace),
      ('EE', onScientificE),
      (')', onCloseGroup),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final (label, fn) in buttons)
          _PadKey(label: label, onTap: fn),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({required this.label, required this.onTap, this.glow = false});
  final String label;
  final VoidCallback onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: glow ? scheme.primaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: glow ? scheme.onPrimaryContainer : scheme.onSurface,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// lib/ui/palette/variables_tab.dart
import 'package:flutter/material.dart';

class VariablesTab extends StatelessWidget {
  const VariablesTab({
    super.key,
    required this.existing,
    required this.onPick,
    required this.onNew,
  });

  final List<({String identifier, bool isInput})> existing;
  final void Function(String identifier) onPick;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New variable'),
            onPressed: onNew,
          ),
          for (final v in existing)
            ActionChip(
              backgroundColor: v.isInput
                  ? scheme.tertiaryContainer
                  : scheme.secondaryContainer,
              label: Text(v.identifier,
                  style: const TextStyle(fontFamily: 'monospace')),
              onPressed: () => onPick(v.identifier),
            ),
        ],
      ),
    );
  }
}
```

```dart
// lib/ui/palette/operators_tab.dart
import 'package:flutter/material.dart';

class OperatorsTab extends StatelessWidget {
  const OperatorsTab({
    super.key,
    required this.isOperatorContext,
    required this.onOperator,
    required this.onOpenGroup,
    required this.onCloseGroup,
  });

  final bool isOperatorContext;
  final void Function(String op) onOperator;
  final VoidCallback onOpenGroup;
  final VoidCallback onCloseGroup;

  @override
  Widget build(BuildContext context) {
    final ops = <(String, String)>[
      ('+', '+'),
      ('−', '-'),
      ('×', '*'),
      ('÷', '/'),
      ('^', '^'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final (display, value) in ops)
            _PalKey(
              label: display,
              onTap: () => onOperator(value),
              glow: isOperatorContext,
              fg: scheme.primary,
            ),
          _PalKey(label: '(', onTap: onOpenGroup, glow: !isOperatorContext, fg: scheme.outline),
          _PalKey(label: ')', onTap: onCloseGroup, glow: false, fg: scheme.outline),
        ],
      ),
    );
  }
}

class _PalKey extends StatelessWidget {
  const _PalKey({
    required this.label,
    required this.onTap,
    required this.glow,
    required this.fg,
  });
  final String label;
  final VoidCallback onTap;
  final bool glow;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: glow ? scheme.primaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: glow ? scheme.onPrimaryContainer : fg,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// lib/ui/palette/functions_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:equation_solver_app/engine/op_registry.dart';
import 'function_picker_sheet.dart';

class FunctionsTab extends ConsumerWidget {
  const FunctionsTab({super.key, required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advancedAsync = ref.watch(advancedFunctionsEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    return advancedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (advanced) {
        final entries = OpRegistry.functions.entries
            .where((e) => advanced || e.value.category == OpCategory.basic)
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      advanced
                          ? 'Advanced functions on'
                          : 'Advanced functions off',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  Switch(
                    value: advanced,
                    onChanged: (v) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setAdvancedFunctionsEnabled(v);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.all(6),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final e in entries)
                    Material(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      elevation: 1,
                      child: InkWell(
                        onTap: onPick,
                        borderRadius: BorderRadius.circular(8),
                        child: Center(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
```

> **NOTE:** Functions tab calls `onPick` regardless of which specific function was tapped. The editor host page will handle showing the picker sheet for "search" + actually returning the chosen function — OR we change the tab to inject the function directly. The simpler path: the tab itself opens the picker sheet on any tap, and the picker's selection is passed back to the editor via `onPick` returning the chosen function name.
>
> Adjust the FunctionsTab so each function grid item directly calls a `void Function(String name, int arity)` callback rather than `onPick`. Update Palette accordingly. Implementer should restructure this small detail during execution.

#### Commit

```bash
git add lib/ui/palette/
git commit -m "feat(palette): tabs (numbers/vars/operators/functions) with progressive disclosure"
```

---

### Task 6: Editor host page

**Files:**
- Create: `lib/ui/editor/entry_editor_page.dart`

The host page brings it all together. It owns the `EditorState` instance, wires sheet/popover invocations from chip taps, dispatches palette actions, shows the banner, runs save.

I'll write the host page in execution; the full body is too long to include in the plan. The shape:

- Receives `entryId?`, `folderId`. If entryId given, loads from storage.
- Holds `EditorState` as a `ChangeNotifier` (use `ListenableBuilder` or a Riverpod `ChangeNotifierProvider`).
- AppBar: back arrow, inline-editable entry name, undo button (enabled when `state.history.canUndo`), redo button, save button (enabled when no banner errors).
- Banner: top, only if `state.bannerError != null`.
- Body scroll: list of formula rows. Each row = Card with output chip on the left, `=`, ChipRenderer to the right. Active row gets emphasis.
- Bottom: `Palette` widget with all callbacks wired to `state`.
- Save: flatten each row, parse, resolve, persist via existing repos.

#### Commit

After implementation and successful Linux build:

```bash
git add lib/ui/editor/entry_editor_page.dart
git commit -m "feat(editor): host page wiring chips + palette + save flow"
```

---

### Task 7: Wire navigation from entry list to editor

**Files:**
- Modify: `lib/ui/entry_list_page.dart`

Replace the two "Formula editor coming in next update" snackbars with actual `Navigator.push` to the new `EntryEditorPage`. Also enhance the `_duplicate` helper to also duplicate equations and variables (not just name+description).

```dart
// FAB onPressed:
onPressed: () async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EntryEditorPage(folderId: folder.id),
    ),
  );
  refresh();
},

// Menu 'edit':
if (action == 'edit') {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EntryEditorPage(
        folderId: folder.id,
        entryId: entry.id,
      ),
    ),
  );
  refresh();
}
```

For `_duplicate`, load the entry's equations and variables, create a new entry, replaceAll equations with the same drafts (new entryId), replaceAll variable_meta with the same drafts.

#### Commit

```bash
git add lib/ui/entry_list_page.dart
git commit -m "feat(ui): wire FAB + Edit menu to chip editor; deep duplicate including equations + vars"
```

---

### Task 8: Draft auto-save (SharedPreferences)

**Files:**
- Create: `lib/state/editor_drafts_provider.dart`
- Modify: `lib/ui/editor/entry_editor_page.dart` (subscribe to state changes, debounced save; offer restore on open)

Draft key: `editor.draft.<entryId-or-new-<folderId>>`. Body: JSON of `{name, description, rows: [{output, chips}]}`. Use the existing `astToJson`-style approach but for chips: round-trip via `flatten` and parse on restore. Simpler: store chip flatten string per row plus output name.

#### Commit

```bash
git add lib/state/editor_drafts_provider.dart lib/ui/editor/entry_editor_page.dart
git commit -m "feat(editor): SharedPreferences-backed draft auto-save with restore banner"
```

---

### Task 9: Verify, build, tag

Run `flutter test` (engine/storage/state — UI tests omitted as in Plan A).
Run `flutter build linux --debug` to verify the app compiles.
Run `flutter build apk --release --no-tree-shake-icons` to produce the shipping APK.

Tag the result `ui-editor-v1`.

#### Commit

No code commit; just tag.

```bash
git tag -a ui-editor-v1 -m "Chip-flow editor complete (Plan B): full §6 implementation"
```

---

## Plan B — Self-review

**Spec coverage:**
- §4 chip data model → Task 1 ✓
- §5 editor screen + per-chip taps → Tasks 3, 4, 6 ✓
- §6 variable creation flow (3 modes, role+unit) → Task 4 ✓
- §7 palette tabs + progressive disclosure → Task 5 ✓
- §8 multi-row + drag/swipe → Task 6 (in the host page) ✓
- §9 undo/redo + drafts → Tasks 2, 8 ✓
- §11 errors + banner → Task 6 (banner logic in the host page) ✓
- Wire navigation → Task 7 ✓

**Placeholder scan:** A few NOTEs flagged in Task 4 and Task 5 where the implementer should make small structural adjustments during execution. These are minor (e.g., OpDef arity field, FunctionsTab callback shape). Acceptable for an in-flight implementation.

**Type consistency:** ChipNode types, Caret, CaretPath, EditorState, EditorRow, RowSnapshot, HistorySnapshot, ChipHistory, DraftVarMeta all defined in Tasks 1-2 before being used in Tasks 3-8.

Plan B is ready to execute.
