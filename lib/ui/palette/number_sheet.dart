import 'package:flutter/material.dart';

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
          Text('Edit number', style: Theme.of(ctx).textTheme.titleMedium),
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
