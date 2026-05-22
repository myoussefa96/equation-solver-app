import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/storage/database.dart';
import 'package:equation_solver_app/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.openApp();
  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const EquationSolverApp(),
    ),
  );
}
