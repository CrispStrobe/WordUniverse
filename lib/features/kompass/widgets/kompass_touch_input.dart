import 'package:flutter/material.dart';

import '../models/kompass_models.dart';
import '../models/kompass_touch.dart';
import 'kompass_strings.dart';
import 'kompass_ui.dart';

const _selected = Color(0xFFE2F2EC);
const _selectedEdge = Color(0xFF247968);
const _edge = Color(0xFFCAD6E2);

/// Draws one touch widget. [state] is the widget's own taps (saved with the
/// session draft); every change reports the new state and the text it gives
/// each part, which is what the grader reads.
class KompassTouchInput extends StatelessWidget {
  final KompassTouch touch;
  final Map<String, dynamic> state;
  final String? prompt;
  final bool enabled;
  final void Function(Map<String, dynamic> state, Map<String, String> values)
      onChanged;

  const KompassTouchInput({
    super.key,
    required this.touch,
    required this.state,
    required this.onChanged,
    this.prompt,
    this.enabled = true,
  });

  void _set(Map<String, dynamic> next) {
    if (enabled) onChanged(next, touch.values(next));
  }

  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    final body = switch (touch.kind) {
      'choice' => _choice(),
      'rank' => _rank(s),
      'select' => _select(),
      'span' => _span(),
      'fix' => _fix(s),
      'split' => _split(s),
      'letters' => _letters(s),
      'punctuate' => _punctuate(s),
      'arrange' => _arrange(s),
      _ => const SizedBox.shrink(),
    };
    final hint = _hint(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (prompt != null && prompt!.isNotEmpty) ...[
          Text(prompt!,
              style: const TextStyle(
                  color: kompassInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  height: 1.5)),
          const SizedBox(height: 6),
        ],
        if (hint != null) ...[
          Text(hint,
              style: const TextStyle(
                  color: kompassMuted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
        ],
        body,
      ]),
    );
  }

  String? _hint(KompassStrings s) => switch (touch.kind) {
        'rank' => s.choose('Tippe die Sätze in der richtigen Reihenfolge an.',
            'Tap the sentences in the right order.'),
        'select' => touch.partIds.length > 1
            ? s.choose('Tippe die Wörter an, die du verbessern musst.',
                'Tap the words that need correcting.')
            : s.choose(
                'Tippe die passenden Wörter an.', 'Tap the right words.'),
        'span' => s.choose(
            'Tippe auf den ersten und den letzten Buchstaben des Wortteils.',
            'Tap the first and the last letter of the word part.'),
        'fix' => s.choose(
            'Tippe ein falsch geschriebenes Wort an und wähle die richtige Schreibung.',
            'Tap a misspelt word and choose the right spelling.'),
        'split' => s.choose(
            'Tippe zwischen die Wörter, um die Satzglieder zu trennen.',
            'Tap between the words to separate the sentence parts.'),
        'letters' => s.choose(
            'Tippe zwischen die Buchstaben, um die Wörter zu trennen. Tippe dann unten auf ein Wort, um es groß oder klein zu schreiben.',
            'Tap between the letters to separate the words. Then tap a word below to switch between capital and small letter.'),
        'punctuate' => s.choose(
            'Tippe auf eine Lücke und dann auf ein Satzzeichen.',
            'Tap a gap, then a punctuation mark.'),
        'arrange' => s.choose('Tippe die Bausteine der Reihe nach an.',
            'Tap the pieces in order.'),
        _ => null,
      };

  // ---------------------------------------------------------------- choice
  Widget _choice() {
    final picked = state['i'] as int?;
    final template = touch.template;
    final chips = Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < touch.options.length; i++)
        _chip(
          key: ValueKey('touch-${touch.partIds.first}-$i'),
          label: touch.options[i],
          selected: picked == i,
          onTap: () => _set({'i': picked == i ? null : i}),
          large: template != null,
        ),
    ]);
    if (template == null) return chips;
    final pieces = template.split('{}');
    final fill = picked == null ? null : touch.options[picked];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(
        TextSpan(
            style: const TextStyle(
                color: kompassInk, fontSize: 26, fontWeight: FontWeight.w600),
            children: [
              TextSpan(text: pieces.first),
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 40),
                    decoration: BoxDecoration(
                        color: fill == null ? Colors.white : _selected,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: fill == null ? _edge : _selectedEdge,
                            width: 2)),
                    child: Text(fill ?? ' ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _selectedEdge,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                  )),
              if (pieces.length > 1) TextSpan(text: pieces.sublist(1).join()),
            ]),
      ),
      const SizedBox(height: 12),
      chips,
    ]);
  }

  // ------------------------------------------------------------------ rank
  Widget _rank(KompassStrings s) {
    final order = _ints(state['order']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var row = 0; row < touch.labels.length; row++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _card(
            key: ValueKey('touch-rank-$row'),
            selected: order.contains(row),
            onTap: () => _set({
              'order': order.contains(row)
                  ? (List<int>.from(order)..remove(row))
                  : [...order, row]
            }),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: order.contains(row) ? _selectedEdge : Colors.white,
                    border: Border.all(
                        color: order.contains(row) ? _selectedEdge : _edge)),
                child: Text(
                    order.contains(row) ? '${order.indexOf(row) + 1}' : '',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(touch.labels[row],
                      style: const TextStyle(
                          color: kompassInk, fontSize: 16, height: 1.4))),
            ]),
          ),
        ),
      if (order.isNotEmpty) _reset(s, () => _set({'order': <int>[]})),
    ]);
  }

  // ---------------------------------------------------------------- select
  Widget _select() {
    final chosen = _ints(state['sel']).toSet();
    final limit = touch.partIds.length > 1 ? touch.partIds.length : null;
    return Wrap(spacing: 8, runSpacing: 10, children: [
      for (var i = 0; i < touch.words.length; i++)
        _chip(
          key: ValueKey('touch-word-${touch.partIds.first}-$i'),
          label: touch.words[i],
          selected: chosen.contains(i),
          onTap: () {
            final next = Set<int>.from(chosen);
            if (!next.remove(i)) {
              if (limit != null && next.length >= limit) return;
              next.add(i);
            }
            _set({'sel': next.toList()..sort()});
          },
        ),
    ]);
  }

  // ------------------------------------------------------------------ span
  Widget _span() {
    final a = state['a'] as int?, b = state['b'] as int?;
    final lo = a == null ? null : (b == null || a < b ? a : b);
    final hi = a == null ? null : (b == null ? a : (a < b ? b : a));
    return Wrap(spacing: 4, runSpacing: 6, children: [
      for (var i = 0; i < touch.word.length; i++)
        _letterTile(
          key: ValueKey('touch-letter-${touch.partIds.first}-$i'),
          letter: touch.word[i],
          selected: lo != null && i >= lo && i <= hi!,
          onTap: () {
            if (a == null || b != null) {
              _set({'a': i, 'b': null});
            } else {
              _set({'a': a, 'b': i});
            }
          },
        ),
    ]);
  }

  // ------------------------------------------------------------------- fix
  Widget _fix(KompassStrings s) {
    final chosen = Map<String, dynamic>.from(state['ch'] as Map? ?? {});
    final open = state['open'] as int?;
    final spellings = touch.spellings;
    final words = touch.words;
    String shown(int i) {
      final c = chosen['$i'];
      final core = touchCore(words[i]);
      return c is String ? words[i].replaceFirst(core, c) : words[i];
    }

    final changed = {
      for (final e in chosen.entries)
        if (e.value != touchCore(words[int.parse(e.key)])) int.parse(e.key)
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 10, children: [
        for (var i = 0; i < words.length; i++)
          spellings[i].isEmpty
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Text(words[i],
                      style: const TextStyle(color: kompassInk, fontSize: 18)))
              : _chip(
                  key: ValueKey('touch-fix-$i'),
                  label: shown(i),
                  selected: changed.contains(i) || open == i,
                  onTap: () => _set({...state, 'open': open == i ? null : i}),
                ),
      ]),
      if (open != null && open < words.length) ...[
        const SizedBox(height: 14),
        Text(
            s.choose('Wie schreibt man dieses Wort richtig?',
                'How is this word spelt correctly?'),
            style: const TextStyle(color: kompassMuted, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final spelling in ([
            touchCore(words[open]),
            ...spellings[open],
          ]..sort()))
            _chip(
              key: ValueKey('touch-spelling-$open-$spelling'),
              label: spelling,
              large: true,
              selected: (chosen['$open'] ?? touchCore(words[open])) == spelling,
              onTap: () {
                final next = Map<String, dynamic>.from(chosen);
                if (spelling == touchCore(words[open])) {
                  next.remove('$open');
                } else {
                  next['$open'] = spelling;
                }
                _set({'ch': next, 'open': null});
              },
            ),
        ]),
      ],
    ]);
  }

  // ----------------------------------------------------------------- split
  Widget _split(KompassStrings s) {
    final cuts = _ints(state['cuts']).toSet();
    final words = touch.words;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          children: [
            for (var i = 0; i < words.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(words[i],
                    style: const TextStyle(color: kompassInk, fontSize: 20)),
              ),
              if (i < words.length - 1)
                _gap(
                  key: ValueKey('touch-cut-$i'),
                  active: cuts.contains(i),
                  bar: true,
                  onTap: () => _set({
                    'cuts': (Set<int>.from(cuts)..toggle(i)).toList()..sort()
                  }),
                ),
            ],
          ]),
      if (cuts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final group in touch.splitWords(cuts)) _pill(group.join(' ')),
        ]),
        _reset(s, () => _set({'cuts': <int>[]})),
      ],
    ]);
  }

  // --------------------------------------------------------------- letters
  Widget _letters(KompassStrings s) {
    final cuts = _ints(state['cuts']).toSet();
    final caps = _ints(state['caps']).toSet();
    final letters = touch.letters;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            for (var i = 0; i < letters.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(letters[i],
                    style: const TextStyle(
                        color: kompassInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              if (i < letters.length - 1)
                _gap(
                  key: ValueKey('touch-cut-$i'),
                  active: cuts.contains(i),
                  bar: true,
                  narrow: true,
                  onTap: () => _set({
                    ...state,
                    'cuts': (Set<int>.from(cuts)..toggle(i)).toList()..sort(),
                  }),
                ),
            ],
          ]),
      if (cuts.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (final (start, word) in touch.letterWords(cuts, caps))
            _chip(
              key: ValueKey('touch-case-$start'),
              label: word,
              selected: caps.contains(start),
              onTap: () => _set({
                ...state,
                'caps': (Set<int>.from(caps)..toggle(start)).toList()..sort(),
              }),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(touch.end,
                style: const TextStyle(color: kompassInk, fontSize: 18)),
          ),
        ]),
        _reset(s, () => _set({'cuts': <int>[], 'caps': <int>[]})),
      ],
    ]);
  }

  // ------------------------------------------------------------- punctuate
  Widget _punctuate(KompassStrings s) {
    final gaps = touch.punctuationGaps(state);
    final at = state['at'] as int?;
    final words = touch.words;
    void setGaps(List<String> next, int? cursor) =>
        _set({'gaps': next, 'at': cursor});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          children: [
            for (var i = 0; i < words.length; i++) ...[
              Text(words[i],
                  style: const TextStyle(color: kompassInk, fontSize: 20)),
              _gap(
                key: ValueKey('touch-gap-$i'),
                active: at == i,
                label: gaps[i].isEmpty ? '' : gaps[i],
                filled: gaps[i].isNotEmpty,
                onTap: () => setGaps(gaps, at == i ? null : i),
              ),
            ],
          ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final mark in touch.marks)
          _chip(
            key: ValueKey('touch-mark-$mark'),
            label: mark,
            large: true,
            selected: false,
            onTap: at == null
                ? null
                : () => setGaps([
                      for (var i = 0; i < gaps.length; i++)
                        i == at ? gaps[i] + mark : gaps[i]
                    ], at),
          ),
        IconButton(
          key: const ValueKey('touch-mark-delete'),
          tooltip: s.choose('Zeichen löschen', 'Delete mark'),
          onPressed: at == null || gaps[at].isEmpty || !enabled
              ? null
              : () => setGaps([
                    for (var i = 0; i < gaps.length; i++)
                      i == at
                          ? gaps[i].substring(0, gaps[i].length - 1)
                          : gaps[i]
                  ], at),
          icon: const Icon(Icons.backspace_outlined),
        ),
      ]),
      if (gaps.any((g) => g.isNotEmpty)) ...[
        const SizedBox(height: 12),
        _pill(assemblePunctuation(words, gaps)),
      ],
    ]);
  }

  // --------------------------------------------------------------- arrange
  Widget _arrange(KompassStrings s) {
    final seq = _ints(state['seq']);
    final tiles = touch.tiles;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _edge)),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (var k = 0; k < seq.length; k++)
            _chip(
              key: ValueKey('touch-placed-$k'),
              label: tiles[seq[k]],
              selected: true,
              onTap: () => _set({'seq': List<int>.from(seq)..removeAt(k)}),
            ),
          if (seq.length == tiles.length && touch.end.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(touch.end,
                    style: const TextStyle(color: kompassInk, fontSize: 18))),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < tiles.length; i++)
          if (!seq.contains(i))
            _chip(
              key: ValueKey('touch-tile-$i'),
              label: tiles[i],
              selected: false,
              onTap: () => _set({
                'seq': [...seq, i]
              }),
            ),
      ]),
    ]);
  }

  // ------------------------------------------------------------- pieces
  Widget _chip(
      {required Key key,
      required String label,
      required bool selected,
      required VoidCallback? onTap,
      bool large = false}) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled && onTap != null,
      child: Material(
        color: selected ? _selected : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints:
                BoxConstraints(minWidth: large ? 64 : 44, minHeight: 48),
            padding:
                EdgeInsets.symmetric(horizontal: large ? 18 : 12, vertical: 10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? _selectedEdge : _edge,
                    width: selected ? 2 : 1)),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: kompassInk,
                    fontSize: large ? 22 : 17,
                    fontWeight: large ? FontWeight.w600 : FontWeight.normal)),
          ),
        ),
      ),
    );
  }

  Widget _card(
          {required Key key,
          required bool selected,
          required VoidCallback onTap,
          required Widget child}) =>
      Material(
        color: selected ? _selected : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? _selectedEdge : _edge,
                    width: selected ? 2 : 1)),
            child: child,
          ),
        ),
      );

  Widget _letterTile(
          {required Key key,
          required String letter,
          required bool selected,
          required VoidCallback onTap}) =>
      _chip(
          key: key,
          label: letter,
          selected: selected,
          onTap: onTap,
          large: true);

  /// A tappable gap between two words or letters.
  /// A tappable gap between two words or letters. A bar gap shows a faint
  /// line until it is tapped; a punctuation gap is a small box that grows
  /// with the marks put into it.
  Widget _gap(
      {required Key key,
      required bool active,
      required VoidCallback onTap,
      String label = '',
      bool bar = false,
      bool filled = false,
      bool narrow = false}) {
    final on = active || filled;
    final Widget mark = bar
        ? (active
            ? const Text('|',
                style: TextStyle(
                    color: _selectedEdge,
                    fontSize: 26,
                    fontWeight: FontWeight.bold))
            : Container(width: 2, height: 22, color: const Color(0xFFDCE3EA)))
        : Text(label,
            style: const TextStyle(
                color: _selectedEdge,
                fontSize: 20,
                fontWeight: FontWeight.bold));
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          constraints: BoxConstraints(minWidth: narrow ? 22 : 30),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
              color: active ? _selected : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: bar && !active
                  ? null
                  : Border.all(
                      color: on ? _selectedEdge : const Color(0xFFDCE3EA),
                      width: on ? 2 : 1)),
          child: Center(widthFactor: 1, child: mark),
        ),
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10)),
        child:
            Text(text, style: const TextStyle(color: kompassInk, fontSize: 17)),
      );

  Widget _reset(KompassStrings s, VoidCallback onTap) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: enabled ? onTap : null,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(s.choose('Von vorn', 'Start over')),
        ),
      );
}

/// For an open answer that asks for something from the text: tap a line of
/// the passage to copy it into the answer, instead of typing it out.
class KompassQuotePicker extends StatelessWidget {
  final KompassTouch touch;
  final KompassStimulus stimulus;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const KompassQuotePicker({
    super.key,
    required this.touch,
    required this.stimulus,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    final range = touch.lineRange;
    final lines = stimulus.lines.where((line) {
      final n = int.tryParse(line.label);
      return range == null || (n != null && n >= range.$1 && n <= range.$2);
    }).toList();
    return ExpansionTile(
      key: ValueKey('quote-${touch.partIds.first}'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.format_quote_rounded, color: _selectedEdge),
      title: Text(
          s.choose('Eine Zeile aus dem Text übernehmen',
              'Copy a line from the text'),
          style: const TextStyle(color: kompassInk, fontSize: 15)),
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: value.contains(line.text) ? _selected : Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('quote-line-${line.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: !enabled || value.contains(line.text)
                    ? null
                    : () => onChanged(value.trim().isEmpty
                        ? line.text
                        : '${value.trimRight()}\n${line.text}'),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _edge)),
                  child: Text('${line.label}  ${line.text}',
                      style: const TextStyle(
                          color: kompassInk, fontSize: 15, height: 1.4)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

extension on Set<int> {
  void toggle(int value) {
    if (!remove(value)) add(value);
  }
}

List<int> _ints(dynamic value) => (value as List? ?? const [])
    .whereType<num>()
    .map((v) => v.toInt())
    .toList();
