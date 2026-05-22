import 'package:equation_solver_app/ui/folder_list_page.dart';
import 'package:flutter/material.dart';

class EquationSolverApp extends StatelessWidget {
  const EquationSolverApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Equation Solver',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          appBarTheme: const AppBarTheme(centerTitle: false),
        ),
        home: const FolderListPage(),
      );
}
