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
  bool operator ==(Object o) {
    if (o is! HistorySnapshot || o.rows.length != rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (o.rows[i] != rows[i]) return false;
    }
    return true;
  }

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
