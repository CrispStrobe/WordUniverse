/// Touch answers for Kompass tasks.
///
/// The print task is answered in writing. Most of those answers can be given
/// by tapping instead: both spellings are in the task already ("Ber(g/k)"),
/// the words to mark are on the page, the bars go between the Satzglieder.
/// A task's `touch` list (from kompass4's companion annotations) says how,
/// per part. Each widget yields exactly the text a child would have typed, so
/// the grader and the accepted answers are untouched, and typing stays
/// available as the other way. The rules here mirror kompass4's
/// kompass/touch.py, whose exporter proves that the right taps produce an
/// accepted answer for every part.
library;

const _edge = '.,!?:;„“"»«';
const _opening = {'„', '»'};

String touchCore(String word) {
  var start = 0, end = word.length;
  while (start < end && _edge.contains(word[start])) {
    start++;
  }
  while (end > start && _edge.contains(word[end - 1])) {
    end--;
  }
  return word.substring(start, end);
}

String touchCapitalize(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

/// Words with the marks tapped into each gap (gap i follows word i): closing
/// marks hold on to the word before them, an opening quote to the word after.
String assemblePunctuation(List<String> words, List<String> gaps) {
  final out = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    final gap = i < gaps.length ? gaps[i] : '';
    final marks = gap.split('');
    final closing = marks.where((m) => !_opening.contains(m)).join();
    final opening = marks.where(_opening.contains).join();
    final last = i == words.length - 1;
    out
      ..write(words[i])
      ..write(closing)
      ..write(last ? '' : ' ')
      ..write(opening);
  }
  return out.toString();
}

/// One touch widget of a task, and the text it gives each of its parts.
class KompassTouch {
  final String kind;
  final List<String> partIds;
  final Map<String, dynamic> spec;
  KompassTouch.fromJson(Map<String, dynamic> json)
      : kind = json['kind'] as String,
        partIds = json['parts'] is List
            ? (json['parts'] as List).map((p) => '$p').toList()
            : ['${json['part']}'],
        spec = Map.unmodifiable(json);

  static const kinds = {
    'choice',
    'rank',
    'select',
    'span',
    'fix',
    'split',
    'letters',
    'punctuate',
    'arrange',
    'quote',
  };

  List<String> get options => _strings(spec['options']);
  String? get template => spec['template'] as String?;
  List<String> get words => _strings(spec['words']);
  List<String> get labels => _strings(spec['labels']);
  List<String> get tiles => _strings(spec['tiles']);
  List<String> get marks => _strings(spec['marks']);
  String get word => spec['word'] as String? ?? '';
  String get letters => spec['letters'] as String? ?? '';
  String get end => spec['end'] as String? ?? '';
  bool get capitalize => spec['capitalize'] == true;
  List<List<String>> get spellings => (spec['options'] as List? ?? const [])
      .map((o) => _strings(o))
      .toList(growable: false);

  /// Passage lines a quote offers, as 1-based labels; null means all.
  (int, int)? get lineRange {
    final lines = spec['lines'];
    if (lines is List && lines.length == 2) {
      return ((lines[0] as num).toInt(), (lines[1] as num).toInt());
    }
    return null;
  }

  String choiceValue(String option) =>
      template == null ? option : template!.replaceAll('{}', option);

  /// The text each part gets from [state]; '' where nothing is tapped yet.
  Map<String, String> values(Map<String, dynamic> state) {
    final out = {for (final id in partIds) id: ''};
    switch (kind) {
      case 'choice':
        final i = state['i'];
        if (i is int && i >= 0 && i < options.length) {
          out[partIds.first] = choiceValue(options[i]);
        }
      case 'rank':
        final order = _ints(state['order']);
        for (var row = 0; row < partIds.length; row++) {
          final at = order.indexOf(row);
          if (at >= 0) out[partIds[row]] = '${at + 1}';
        }
      case 'select':
        final chosen = _ints(state['sel'])..sort();
        final cores = words.map(touchCore).toList();
        if (partIds.length == 1) {
          out[partIds.first] = chosen.map((i) => cores[i]).join(' ');
        } else {
          for (var j = 0; j < partIds.length && j < chosen.length; j++) {
            final w = cores[chosen[j]];
            out[partIds[j]] = capitalize ? touchCapitalize(w) : w;
          }
        }
      case 'span':
        final a = state['a'], b = state['b'];
        if (a is int && b is int) {
          final lo = a < b ? a : b, hi = a < b ? b : a;
          if (lo >= 0 && hi < word.length) {
            out[partIds.first] = word.substring(lo, hi + 1);
          }
        }
      case 'fix':
        final chosen = Map<String, dynamic>.from(state['ch'] as Map? ?? {});
        final changed = <(int, String)>[
          for (final e in chosen.entries)
            if (int.tryParse(e.key) case final i?)
              if (i >= 0 &&
                  i < words.length &&
                  e.value is String &&
                  e.value != touchCore(words[i]))
                (i, e.value as String),
        ]..sort((x, y) => x.$1.compareTo(y.$1));
        for (var j = 0; j < partIds.length && j < changed.length; j++) {
          out[partIds[j]] = changed[j].$2;
        }
      case 'split':
        final cuts = _ints(state['cuts']).toSet();
        if (cuts.isEmpty) break;
        final groups = splitWords(cuts);
        for (var j = 0; j < partIds.length && j < groups.length; j++) {
          out[partIds[j]] = j == partIds.length - 1
              ? groups.sublist(j).expand((g) => g).join(' ')
              : groups[j].join(' ');
        }
      case 'letters':
        final cuts = _ints(state['cuts']).toSet();
        if (cuts.isEmpty) break;
        final sentence = letterWords(cuts, _ints(state['caps']).toSet())
                .map((w) => w.$2)
                .join(' ') +
            end;
        for (final id in partIds) {
          out[id] = sentence;
        }
      case 'punctuate':
        final gaps = punctuationGaps(state);
        if (gaps.every((g) => g.isEmpty)) break;
        final sentence = assemblePunctuation(words, gaps);
        for (final id in partIds) {
          out[id] = sentence;
        }
      case 'arrange':
        final seq = _ints(state['seq']);
        if (seq.isEmpty) break;
        final text = seq.map((i) => tiles[i]).join(' ') +
            (seq.length == tiles.length ? end : '');
        for (final id in partIds) {
          out[id] = text;
        }
    }
    return out;
  }

  /// The sentence's words in groups, cut after the word indices in [cuts].
  List<List<String>> splitWords(Set<int> cuts) {
    final groups = <List<String>>[[]];
    final cores = words.map(touchCore).toList();
    for (var i = 0; i < cores.length; i++) {
      groups.last.add(cores[i]);
      if (cuts.contains(i) && i < cores.length - 1) groups.add([]);
    }
    return groups;
  }

  /// (start letter index, word as shown) for the letters cut after [cuts];
  /// lower case unless its start is in [caps].
  List<(int, String)> letterWords(Set<int> cuts, Set<int> caps) {
    final out = <(int, String)>[];
    var start = 0;
    for (var i = 0; i < letters.length; i++) {
      if (cuts.contains(i) || i == letters.length - 1) {
        final w = letters.substring(start, i + 1).toLowerCase();
        out.add((start, caps.contains(start) ? touchCapitalize(w) : w));
        start = i + 1;
      }
    }
    return out;
  }

  List<String> punctuationGaps(Map<String, dynamic> state) {
    final raw = state['gaps'];
    return [
      for (var i = 0; i < words.length; i++)
        raw is List && i < raw.length && raw[i] is String
            ? raw[i] as String
            : '',
    ];
  }
}

List<String> _strings(dynamic value) =>
    (value as List? ?? const []).map((v) => '$v').toList(growable: false);
List<int> _ints(dynamic value) => (value as List? ?? const [])
    .whereType<num>()
    .map((v) => v.toInt())
    .toList();
