import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('engine files do not import package:flutter', () {
    final engineDir = Directory('lib/engine');
    expect(engineDir.existsSync(), isTrue, reason: 'lib/engine/ must exist');

    final dartFiles = engineDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final violations = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('import') && line.contains('package:flutter')) {
          violations.add('${file.path}:${i + 1}: $line');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'engine layer must be pure Dart — found Flutter imports:\n${violations.join('\n')}',
    );
  });
}
