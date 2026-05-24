import 'package:equation_solver_app/engine/dependency_resolver.dart';
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
      NumberChip(:final text) =>
        _basic(context, text, scheme.surface, scheme.onSurface),
      VarChip(:final name) => _varPill(context, name, scheme),
      ConstChip(:final name) => _basic(
          context,
          _renderConstName(name),
          scheme.surfaceContainerHighest,
          scheme.onSurface,
        ),
      OpChip(:final op) => _basic(
          context,
          _renderOp(op),
          scheme.surface,
          scheme.primary,
          weight: FontWeight.bold,
        ),
      UnaryMinusChip(:final operand) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _basic(context, '−', scheme.surface, scheme.primary,
                weight: FontWeight.bold),
            ChipWidget(
              chip: operand,
              onTap: onTap,
              onLongPress: onLongPress,
              roleOf: roleOf,
              childRenderer: childRenderer,
            ),
          ],
        ),
      GroupChip(:final children) =>
        _container(context, '(', ')', childRenderer(children)),
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
      VarRole.output ||
      VarRole.intermediate =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
      null => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return _basic(context, name, bg, fg);
  }

  Widget _container(
      BuildContext context, String open, String close, Widget body) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(open,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 22, color: scheme.outline)),
        body,
        Text(close,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 22, color: scheme.outline)),
      ],
    );
  }

  Widget _function(
      BuildContext context, String name, List<List<ChipNode>> args) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(left: 1, top: 2, bottom: 2),
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
                    child: Text(
                      ',',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        color: scheme.outline,
                      ),
                    ),
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
