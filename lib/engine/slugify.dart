String slugify(String label) {
  final sb = StringBuffer();
  for (final r in label.runes) {
    final c = String.fromCharCode(r);
    if (_isAllowed(c)) {
      sb.write(c);
    } else {
      sb.write('_');
    }
  }
  var s = sb.toString();
  // Collapse runs of underscores and trim leading/trailing.
  s = s.replaceAll(RegExp(r'_+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.isEmpty) return '_';
  // Identifier must not start with a digit.
  if (RegExp(r'^[0-9]').hasMatch(s)) s = '_$s';
  return s;
}

bool _isAllowed(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x30 && u <= 0x39) // 0-9
      || (u >= 0x41 && u <= 0x5A) // A-Z
      || (u >= 0x61 && u <= 0x7A) // a-z
      || c == '_';
}

class SlugAllocator {
  SlugAllocator({Set<String> reserved = const {}}) : _used = {...reserved};

  final Set<String> _used;

  String allocate(String label) {
    final base = slugify(label);
    if (!_used.contains(base)) {
      _used.add(base);
      return base;
    }
    var n = 2;
    while (_used.contains('${base}_$n')) {
      n++;
    }
    final result = '${base}_$n';
    _used.add(result);
    return result;
  }
}
