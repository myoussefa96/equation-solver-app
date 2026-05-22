import 'package:equation_solver_app/state/db_provider.dart';
import 'package:equation_solver_app/ui/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../storage/_test_db.dart';

void main() {
  test('app bootstrap can be instantiated with database provider', () async {
    final db = await openTestDb();

    const app = EquationSolverApp();
    expect(app, isNotNull);

    final scope = ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: app,
    );
    expect(scope, isNotNull);
  });
}
