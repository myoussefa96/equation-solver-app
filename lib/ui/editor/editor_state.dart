import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:equation_solver_app/ui/editor/chip_history.dart';
import 'package:equation_solver_app/ui/editor/chip_node.dart';
import 'package:flutter/foundation.dart';

class CaretPath {
  CaretPath({required this.parent, required this.index});
  final List<ChipNode> parent;
  final int index;
}

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
  EditorRow({this.output, List<ChipNode>? chips})
      : chips = chips ?? <ChipNode>[];

  VarChip? output;
  List<ChipNode> chips;
  CaretPath? caret;
  String? rowError;
}

class EditorState extends ChangeNotifier {
  EditorState({
    required this.entryId,
    required this.folderId,
    required String entryName,
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
            .map((r) => RowSnapshot(
                  output: r.output,
                  chips: _deepCopy(r.chips),
                ))
            .toList(),
      );

  static List<ChipNode> _deepCopy(List<ChipNode> list) {
    return list.map(_copyOne).toList();
  }

  static ChipNode _copyOne(ChipNode c) {
    return switch (c) {
      NumberChip() => c,
      VarChip() => c,
      ConstChip() => c,
      OpChip() => c,
      UnaryMinusChip(:final operand) => UnaryMinusChip(_copyOne(operand)),
      GroupChip(:final children) => GroupChip(_deepCopy(children)),
      FunctionChip(:final name, :final args) =>
        FunctionChip(name, args.map(_deepCopy).toList()),
    };
  }

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
            chips: _deepCopy(s.chips),
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

  void insertAtCaret(ChipNode chip) {
    final row = active;
    final caret = row.caret ??
        CaretPath(parent: row.chips, index: row.chips.length);
    final list = caret.parent;
    list.insert(caret.index.clamp(0, list.length), chip);
    row.caret = CaretPath(parent: list, index: caret.index + 1);
    pushHistory();
    notifyListeners();
  }

  void insertFunction(String name, {int arity = 1}) {
    final fn =
        FunctionChip(name, List.generate(arity, (_) => <ChipNode>[]));
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

  void closeContainer() {
    final row = active;
    row.caret = CaretPath(parent: row.chips, index: row.chips.length);
    notifyListeners();
  }

  void backspace() {
    final row = active;
    final caret = row.caret;
    if (caret == null || caret.index == 0) return;
    caret.parent.removeAt(caret.index - 1);
    row.caret = CaretPath(parent: caret.parent, index: caret.index - 1);
    pushHistory();
    notifyListeners();
  }

  void setCaret(List<ChipNode> parent, int index) {
    final row = active;
    row.caret = CaretPath(parent: parent, index: index);
    notifyListeners();
  }

  void replaceChip(List<ChipNode> parent, int index, ChipNode replacement) {
    if (index < 0 || index >= parent.length) return;
    parent[index] = replacement;
    pushHistory();
    notifyListeners();
  }

  void deleteChip(List<ChipNode> parent, int index) {
    if (index < 0 || index >= parent.length) return;
    parent.removeAt(index);
    final row = active;
    row.caret =
        CaretPath(parent: parent, index: index.clamp(0, parent.length));
    pushHistory();
    notifyListeners();
  }

  void setOutput(int rowIndex, VarChip v) {
    rows[rowIndex].output = v;
    pushHistory();
    notifyListeners();
  }

  void appendDigit(String digit) {
    final row = active;
    final caret = row.caret ??
        CaretPath(parent: row.chips, index: row.chips.length);
    final list = caret.parent;
    // If the chip immediately before caret is a NumberChip, append into it.
    if (caret.index > 0 && list[caret.index - 1] is NumberChip) {
      final existing = list[caret.index - 1] as NumberChip;
      list[caret.index - 1] = NumberChip('${existing.text}$digit');
      pushHistory();
      notifyListeners();
      return;
    }
    // Otherwise start a new NumberChip.
    list.insert(caret.index, NumberChip(digit));
    row.caret = CaretPath(parent: list, index: caret.index + 1);
    pushHistory();
    notifyListeners();
  }
}
