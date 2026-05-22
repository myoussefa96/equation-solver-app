// Build-time script.
// Reads ../equationsolver/equations_data.sql and writes assets/migration_seed.json.
//
// Run: dart run tool/build_seed.dart
//
// The input SQL is the output of:
//   pg_restore --data-only --table=equation_solver_equation_solver \
//     --table=equation_solver_folder -f equations_data.sql latest.dump
//
// We parse only the two COPY blocks: equation_solver_equation_solver and
// equation_solver_folder. The COPY format is tab-separated, one row per line,
// terminated by a line containing only "\.".

import 'dart:convert';
import 'dart:io';

const _sourceSqlPath = '../equationsolver/equations_data.sql';
const _outPath = 'assets/migration_seed.json';

void main(List<String> args) {
  final input = args.isNotEmpty ? args[0] : _sourceSqlPath;
  final out = args.length > 1 ? args[1] : _outPath;

  final lines = File(input).readAsLinesSync();
  final equations = _parseCopyBlock(
    lines,
    tableName: 'equation_solver_equation_solver',
    columns: ['id', 'equation', 'variables', 'description', 'folder', 'name', 'finalvars'],
  );
  final folders = _parseCopyBlock(
    lines,
    tableName: 'equation_solver_folder',
    columns: ['id', 'name'],
  );

  final seedFolders = [
    for (final f in folders)
      {
        'old_id': int.parse(f['id']!),
        'name': f['name'],
      },
  ];
  final seedEntries = [
    for (final e in equations)
      {
        'old_id': int.parse(e['id']!),
        'old_folder_id': int.parse(e['folder']!),
        'name': e['name'],
        'description': e['description'],
        'equations_raw': e['equation'],
        'variables_raw': e['variables'],
        'finalvars_raw': e['finalvars'],
      },
  ];

  final seed = {
    'folders': seedFolders,
    'entries': seedEntries,
  };

  Directory(out.substring(0, out.lastIndexOf('/'))).createSync(recursive: true);
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(seed));
  stdout.writeln(
    'Wrote $out — ${seedFolders.length} folders, ${seedEntries.length} entries.',
  );
}

List<Map<String, String>> _parseCopyBlock(
  List<String> lines, {
  required String tableName,
  required List<String> columns,
}) {
  final result = <Map<String, String>>[];
  final startMarker = RegExp(r'^COPY "public"\."' + tableName + r'"');
  var inBlock = false;
  for (final line in lines) {
    if (!inBlock && startMarker.hasMatch(line)) {
      inBlock = true;
      continue;
    }
    if (inBlock) {
      if (line == r'\.') break;
      final parts = line.split('\t');
      if (parts.length != columns.length) {
        throw StateError(
          'Expected ${columns.length} columns for $tableName, got ${parts.length} in line: $line',
        );
      }
      final row = <String, String>{};
      for (var i = 0; i < columns.length; i++) {
        row[columns[i]] = _decodeCopyField(parts[i]);
      }
      result.add(row);
    }
  }
  if (result.isEmpty) {
    throw StateError('No rows found for $tableName');
  }
  return result;
}

/// Postgres COPY format escape decoder.
/// `\N` -> NULL (surfaced as empty string), `\\` -> `\`, `\n` -> newline,
/// `\t` -> tab, `\r` -> carriage return. Any other character after a
/// backslash is preserved as-is (the backslash is kept verbatim).
String _decodeCopyField(String s) {
  if (s == r'\N') return '';
  final sb = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) == 0x5C /* '\' */ && i + 1 < s.length) {
      final next = s[i + 1];
      switch (next) {
        case r'\': sb.write(r'\'); break;
        case 'n':   sb.write('\n'); break;
        case 't':   sb.write('\t'); break;
        case 'r':   sb.write('\r'); break;
        default:    sb.write(r'\'); sb.write(next); break;
      }
      i++;
    } else {
      sb.write(s[i]);
    }
  }
  return sb.toString();
}
