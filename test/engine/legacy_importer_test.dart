import 'package:equation_solver_app/engine/ast.dart';
import 'package:equation_solver_app/engine/legacy_importer.dart';
import 'package:test/test.dart';

void main() {
  test('imports a single-equation entry from legacy fields', () {
    final seed = {
      'folders': [
        {'old_id': 2, 'name': 'steam ejector sizing'},
      ],
      'entries': [
        {
          'old_id': 6,
          'old_folder_id': 2,
          'name': 'Temperature factor for suction mass of air',
          'description': 'm eq=mair/y(t)',
          'equations_raw': 'y(t) air=(-4.2857*10^-4)*t+1.01',
          'variables_raw': 't',
          'finalvars_raw': 'y(t) air',
        },
      ],
    };

    final folders = LegacyImporter.importSeed(seed);
    expect(folders, hasLength(1));
    expect(folders[0].name, equals('steam ejector sizing'));
    expect(folders[0].entries, hasLength(1));

    final entry = folders[0].entries[0];
    expect(entry.name, contains('Temperature factor'));
    expect(entry.equations, hasLength(1));
    expect(entry.equations[0].outputVar, equals('y_t_air'));
    expect(entry.equations[0].ast, isA<BinaryOp>());

    // Variables: input 't' + output 'y_t_air'
    expect(
      entry.variables.map((v) => v.identifier).toSet(),
      equals({'t', 'y_t_air'}),
    );
    expect(
      entry.variables.firstWhere((v) => v.identifier == 'y_t_air').isFinal,
      isTrue,
    );
  });

  test('handles whitespace-inconsistent variables_raw', () {
    final seed = {
      'folders': [{'old_id': 2, 'name': 'f'}],
      'entries': [
        {
          'old_id': 1,
          'old_folder_id': 2,
          'name': 'q',
          'description': '',
          'equations_raw': 'r = Q + Sv + D',
          'variables_raw': 'Q, Sv, D',
          'finalvars_raw': 'r',
        },
      ],
    };
    final folders = LegacyImporter.importSeed(seed);
    final ids = folders[0].entries[0].variables.map((v) => v.identifier).toSet();
    expect(ids, containsAll({'Q', 'Sv', 'D', 'r'}));
  });

  test('E in formula is treated as the constant, not a variable', () {
    final seed = {
      'folders': [{'old_id': 2, 'name': 'f'}],
      'entries': [
        {
          'old_id': 1,
          'old_folder_id': 2,
          'name': 'u',
          'description': '',
          'equations_raw':
              'u = ((3.126*root((0.9825-E^(-0.3154))/(0.9694-C^(-0.57))))-3.017)',
          'variables_raw': 'E, C',
          'finalvars_raw': 'u',
        },
      ],
    };
    final folders = LegacyImporter.importSeed(seed);
    final vars = folders[0].entries[0].variables.map((v) => v.identifier).toSet();
    // E is a constant, NOT an input variable. C remains.
    expect(vars.contains('E'), isFalse);
    expect(vars, containsAll({'C', 'u'}));
  });

  test('skips an entry whose formula fails to parse, reports it', () {
    final seed = {
      'folders': [{'old_id': 2, 'name': 'f'}],
      'entries': [
        {
          'old_id': 1, 'old_folder_id': 2,
          'name': 'ok',  'description': '',
          'equations_raw': 'a = 1 + 2',
          'variables_raw': '', 'finalvars_raw': 'a',
        },
        {
          'old_id': 2, 'old_folder_id': 2,
          'name': 'broken', 'description': '',
          'equations_raw': 'b = 1 + ',  // trailing operator
          'variables_raw': '', 'finalvars_raw': 'b',
        },
      ],
    };
    final result = LegacyImporter.importSeedWithReport(seed);
    expect(
      result.folders[0].entries.map((e) => e.name).toList(),
      equals(['ok']),
    );
    expect(result.skipped, hasLength(1));
    expect(result.skipped[0].entryName, equals('broken'));
  });
}
