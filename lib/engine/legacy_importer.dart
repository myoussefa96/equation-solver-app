import 'package:meta/meta.dart';
import 'ast.dart';
import 'dependency_resolver.dart';
import 'op_registry.dart';
import 'parsed_entry.dart';
import 'parser.dart';
import 'slugify.dart';

@immutable
class SkippedEntry {
  const SkippedEntry(this.entryName, this.reason);

  final String entryName;
  final String reason;
}

@immutable
class ImportReport {
  const ImportReport(this.folders, this.skipped);

  final List<ParsedFolder> folders;
  final List<SkippedEntry> skipped;
}

abstract final class LegacyImporter {
  /// Import a seed JSON map (the shape produced by `tool/build_seed.dart`).
  /// Throws on structural errors. Skips individual entries that fail to parse;
  /// see [importSeedWithReport] if you want the skip list.
  static List<ParsedFolder> importSeed(Map<String, Object?> seed) =>
      importSeedWithReport(seed).folders;

  static ImportReport importSeedWithReport(Map<String, Object?> seed) {
    final foldersRaw = (seed['folders'] as List).cast<Map<String, Object?>>();
    final entriesRaw = (seed['entries'] as List).cast<Map<String, Object?>>();

    final folders = <int, List<ParsedEntry>>{
      for (final f in foldersRaw) f['old_id']! as int: <ParsedEntry>[],
    };
    final folderNames = <int, String>{
      for (final f in foldersRaw) f['old_id']! as int: f['name']! as String,
    };
    final skipped = <SkippedEntry>[];

    for (final raw in entriesRaw) {
      final name = raw['name']! as String;
      try {
        final entry = _importOne(raw);
        final oldFolderId = raw['old_folder_id']! as int;
        folders[oldFolderId]!.add(entry);
      } on FormatException catch (e) {
        skipped.add(SkippedEntry(name, e.message));
      } on Exception catch (e) {
        skipped.add(SkippedEntry(name, e.toString()));
      }
    }

    final parsedFolders = [
      for (final f in foldersRaw)
        ParsedFolder(
          name: folderNames[f['old_id']!]!,
          entries: folders[f['old_id']!]!,
        ),
    ];
    return ImportReport(parsedFolders, skipped);
  }

  static ParsedEntry _importOne(Map<String, Object?> raw) {
    final name = raw['name']! as String;
    final description = (raw['description'] as String?)?.trim();
    final equationsRaw = (raw['equations_raw']! as String).trim();
    final variablesRaw = (raw['variables_raw'] as String?) ?? '';
    final finalvarsRaw = (raw['finalvars_raw'] as String?) ?? '';

    // 1. Split top-level commas (legacy convention: one entry can hold many
    //    chained equations separated by commas).
    final pieces = _splitTopLevelCommas(equationsRaw);

    // 2. Parse each as `LHS = RHS`.
    final allocator = SlugAllocator(reserved: OpRegistry.constants.keys.toSet());
    final labelToId = <String, String>{};
    String idFor(String label) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('Empty variable label');
      }
      return labelToId.putIfAbsent(trimmed, () => allocator.allocate(trimmed));
    }

    final equations = <EqEntry>[];
    final equationsParsed = <ParsedEquation>[];
    for (final piece in pieces) {
      // Split on top-level "=" — the LHS may be a free-form label like
      // "y(t) air" that isn't a valid identifier in our grammar.
      final eqIdx = _findTopLevelEquals(piece);
      if (eqIdx < 0) {
        throw FormatException('Missing "=" in legacy formula: "$piece"');
      }
      final lhsLabel = piece.substring(0, eqIdx);
      final rhsText = piece.substring(eqIdx + 1);
      final lhsId = idFor(lhsLabel);
      final rhsAst = Parser(rhsText).parseExpression();
      final remappedAst = _remapAst(rhsAst, idFor);
      equations.add(EqEntry(output: lhsId, ast: remappedAst));
      equationsParsed.add(ParsedEquation(outputVar: lhsId, ast: remappedAst));
    }

    // 3. Pre-declare any variables listed in variables_raw.
    final declaredLabels = variablesRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final declared = <String, VarRole?>{};
    for (final lbl in declaredLabels) {
      declared[idFor(lbl)] = null;
    }

    // 4. Resolve.
    final resolved = DependencyResolver.resolve(
      equations,
      declaredVariables: declared,
    );

    // 5. Build variable list with finalvars flagging.
    final finalLabels = finalvarsRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final finalIds = finalLabels.map((l) => labelToId[l]).whereType<String>().toSet();

    final idToLabel = {
      for (final entry in labelToId.entries) entry.value: entry.key,
    };

    final variables = <ParsedVariable>[];
    for (final entry in resolved.roles.entries) {
      final id = entry.key;
      final role = entry.value;
      final label = idToLabel[id] ?? id;
      final isFinal = role == VarRole.output && finalIds.contains(id);
      variables.add(
        ParsedVariable(
          identifier: id,
          displayLabel: label,
          role: role,
          isFinal: isFinal || (role == VarRole.output && finalIds.isEmpty),
        ),
      );
    }

    return ParsedEntry(
      name: name,
      description: description == null || description.isEmpty ? null : description,
      equations: equationsParsed,
      variables: variables,
    );
  }

  /// Walks an AST and replaces Identifier nodes via [idFor]. This is needed
  /// because the legacy parser emits identifiers based on what the formula
  /// text contained; we want them to match the slugified labels we'll show.
  /// In the current dump, identifiers in equations are already valid (no
  /// spaces/parens — those quirks appear only in LHS labels like "y(t) air"),
  /// so this is mostly a pass-through. We keep the remap as a safety net.
  static AstNode _remapAst(AstNode node, String Function(String) idFor) {
    return switch (node) {
      NumberLit() => node,
      Identifier(:final name) => OpRegistry.constants.containsKey(name)
          ? node
          : Identifier(idFor(name)),
      UnaryMinus(:final operand) => UnaryMinus(_remapAst(operand, idFor)),
      BinaryOp(:final op, :final left, :final right) =>
        BinaryOp(op, _remapAst(left, idFor), _remapAst(right, idFor)),
      FunctionCall(:final name, :final args) =>
        FunctionCall(name, args.map((a) => _remapAst(a, idFor)).toList()),
    };
  }

  /// Splits on top-level commas only — commas inside parens are preserved.
  static List<String> _splitTopLevelCommas(String src) {
    final pieces = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final r in src.runes) {
      final c = String.fromCharCode(r);
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        pieces.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    if (buf.toString().trim().isNotEmpty) pieces.add(buf.toString().trim());
    return pieces;
  }

  /// Returns the index of the first top-level "=" (not nested in parens), or -1.
  static int _findTopLevelEquals(String src) {
    var depth = 0;
    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == '=' && depth == 0) {
        return i;
      }
    }
    return -1;
  }
}
