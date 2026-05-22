import 'package:flutter/material.dart';

class SolvePage extends StatelessWidget {
  const SolvePage({super.key, required this.entryId, required this.entryName});

  final int entryId;
  final String entryName;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(entryName)),
        body: const Center(child: Text('Solve — stub')),
      );
}
