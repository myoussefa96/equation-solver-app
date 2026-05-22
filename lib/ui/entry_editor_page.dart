import 'package:flutter/material.dart';

class EntryEditorPage extends StatelessWidget {
  const EntryEditorPage({super.key, this.entryId, required this.folderId});

  final int? entryId;          // null = creating new
  final int folderId;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(entryId == null ? 'New formula' : 'Edit formula'),
        ),
        body: const Center(child: Text('Editor — stub')),
      );
}
