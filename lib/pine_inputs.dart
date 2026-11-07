class PineInput {
  final String name, title, type;
  final dynamic value;
  final List<String> options;
  final double? min, max, step;
  PineInput(
    this.name,
    this.title,
    this.type,
    this.value, {
    this.options = const [],
    this.min,
    this.max,
    this.step,
  });
  bool get numeric => type == 'int' || type == 'float';
}

List<String> splitPineArgs(String s) {
  final out = <String>[];
  int start = 0, depth = 0;
  String quote = '';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote.isNotEmpty) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = '';
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    if ('([{'.contains(c))
      depth++;
    else if (')]}'.contains(c))
      depth--;
    else if (c == ',' && depth == 0) {
      out.add(s.substring(start, i));
      start = i + 1;
    }
  }
  out.add(s.substring(start));
  return out;
}

dynamic pineLiteral(String raw) {
  final s = raw.trim();
  if (s == 'true') return true;
  if (s == 'false') return false;
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))))
    return s.substring(1, s.length - 1);
  return num.tryParse(s);
}

List<PineInput> parsePineInputs(String source) {
  final result = <PineInput>[];
  final re = RegExp(
    r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*input\.(bool|int|float|string|timeframe)\s*\(',
  );
  for (final m in re.allMatches(source)) {
    int i = m.end, depth = 1;
    String q = '';
    for (; i < source.length && depth > 0; i++) {
      final c = source[i];
      if (q.isNotEmpty) {
        if (c == '\\') {
          i++;
        } else if (c == q) {
          q = '';
        }
        continue;
      }
      if (c == '"' || c == "'")
        q = c;
      else if (c == '(')
        depth++;
      else if (c == ')')
        depth--;
    }
    if (depth != 0) continue;
    final args = splitPineArgs(source.substring(m.end, i - 1));
    dynamic value = pineLiteral(args.first);
    String title = m.group(1)!;
    double? min, max, step;
    List<String> options = [];
    for (final a in args) {
      final n = RegExp(
        r'^\s*(defval|title|minval|maxval|step|options)\s*=\s*([\s\S]*)$',
      ).firstMatch(a);
      if (n == null) continue;
      final text = n.group(2)!.trim(), v = pineLiteral(text);
      switch (n.group(1)) {
        case 'defval':
          value = v;
        case 'title':
          title = '${v ?? text}';
        case 'minval':
          min = v is num ? v.toDouble() : null;
        case 'maxval':
          max = v is num ? v.toDouble() : null;
        case 'step':
          step = v is num ? v.toDouble() : null;
        case 'options':
          if (text.startsWith('[') && text.endsWith(']'))
            options = splitPineArgs(text.substring(1, text.length - 1))
                .map((x) => '${pineLiteral(x) ?? x.trim()}')
                .toList();
      }
    }
    if (value != null && !result.any((x) => x.name == m.group(1)))
      result.add(
        PineInput(
          m.group(1)!,
          title,
          m.group(2)!,
          value,
          options: options,
          min: min,
          max: max,
          step: step,
        ),
      );
  }
  return result;
}

List<Map<String, dynamic>> buildCombinations(
  Map<String, Map<String, dynamic>> ranges,
  int maximum,
) {
  if (maximum < 1 || maximum > 500)
    throw const FormatException(
      'Maximum combinations must be between 1 and 500.',
    );
  final selected = ranges.entries.where((e) => e.value['use'] == true).toList();
  if (selected.isEmpty)
    throw const FormatException('Choose at least one numeric parameter.');
  var combos = <Map<String, dynamic>>[{}];
  for (final e in selected) {
    final g = e.value;
    if (g['single'] != null) {
      combos = combos.map((c) => {...c, e.key: g['single']}).toList();
      continue;
    }
    final min = double.tryParse('${g['min']}'),
        max = double.tryParse('${g['max']}'),
        step = double.tryParse('${g['step']}');
    if (min == null ||
        max == null ||
        step == null ||
        !min.isFinite ||
        !max.isFinite ||
        !step.isFinite ||
        max < min ||
        step <= 0)
      throw FormatException('Invalid Min / Max / Step for ${e.key}.');
    final count = ((max - min) / step + 1e-9).floor() + 1;
    if (count * combos.length > maximum)
      throw FormatException(
        'Too many combinations. Increase the step or reduce the range (maximum $maximum).',
      );
    final next = <Map<String, dynamic>>[];
    for (final c in combos) {
      for (var i = 0; i < count; i++) {
        final v = double.parse((min + i * step).toStringAsFixed(10));
        next.add({...c, e.key: g['integer'] == true ? v.round() : v});
      }
    }
    combos = next;
  }
  return combos;
}
