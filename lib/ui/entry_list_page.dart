// entry_list_page.dart
import 'package:equation_solver_app/storage/folders_repo.dart';
import 'package:flutter/material.dart';

class EntryListPage extends StatelessWidget {
  const EntryListPage({super.key, required this.folder});

  final FolderRow folder;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(folder.name)),
        body: const Center(child: Text('Entry list — stub')),
      );
}
