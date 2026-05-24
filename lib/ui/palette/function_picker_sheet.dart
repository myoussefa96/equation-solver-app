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
                  title: Text(
                    e.key,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(_describe(e.value.category)),
                  onTap: () => Navigator.of(ctx)
                      .pop(FunctionPick(e.key, e.value.arity)),
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
        OpCategory.trig => 'Trigonometry',
        OpCategory.trigInverse => 'Inverse trigonometry',
        OpCategory.hyperbolic => 'Hyperbolic',
        OpCategory.rounding => 'Rounding',
        OpCategory.combinatorics => 'Combinatorics',
        OpCategory.more => 'More',
      };
}
