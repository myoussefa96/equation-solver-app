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
  final void Function(List<ChipNode> parent, int index) onCaretTap;
  final void Function(List<ChipNode> parent, int index, ChipNode chip)
      onChipTap;
  final void Function(List<ChipNode> parent, int index, ChipNode chip)
      onChipLongPress;
  final VarRoleLookup roleOf;

  @override
  Widget build(BuildContext context) => _renderList(context, chips);

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
