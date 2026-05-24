import 'package:equation_solver_app/storage/variable_meta_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.variable,
    required this.value,
    this.emphasis = false,
    this.errorMessage,
  });

  final VariableMetaRow variable;
  final double? value;
  final bool emphasis;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = errorMessage != null;

    return Card(
      shape: hasError
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.error, width: 2),
            )
          : null,
      color: hasError
          ? scheme.errorContainer
          : (emphasis ? scheme.primaryContainer : null),
      child: ListTile(
        title: Text(
          variable.displayLabel,
          style: TextStyle(
            fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
            color: hasError ? scheme.onErrorContainer : null,
          ),
        ),
        subtitle: hasError
            ? Text(errorMessage!,
                style: TextStyle(color: scheme.onErrorContainer))
            : (variable.unit == null ? null : Text(variable.unit!)),
        trailing: hasError
            ? Icon(Icons.error_outline, color: scheme.error)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value == null ? '—' : _format(value!),
                    style: TextStyle(
                      fontSize: emphasis ? 22 : 16,
                      fontWeight:
                          emphasis ? FontWeight.bold : FontWeight.w500,
                      color: emphasis ? scheme.onPrimaryContainer : null,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy value',
                      onPressed: () async {
                        final formatted = _format(value!);
                        await Clipboard.setData(
                            ClipboardData(text: formatted));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied $formatted')),
                          );
                          HapticFeedback.selectionClick();
                        }
                      },
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  static String _format(double v) {
    if (v == 0) return '0';
    final abs = v.abs();
    if (abs >= 1e6 || abs < 1e-3) {
      return v.toStringAsExponential(4);
    }
    return v
        .toStringAsPrecision(6)
        .replaceAll(RegExp(r'(?<=\.\d*?)0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
