import 'package:flutter/material.dart';

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
