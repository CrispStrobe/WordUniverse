import 'package:flutter/material.dart';
import '../models/kompass_models.dart';
import 'kompass_strings.dart';
import 'kompass_ui.dart';

/// Authored print blocks remain available alongside the interactive response.
/// Table cells and logical passage lines never depend on visual line wrapping.
class KompassBlocks extends StatelessWidget {
  final List<Map<String, dynamic>> blocks;
  final bool showResponseLines;
  final bool showChoices;
  final Set<String> redundantParagraphs;
  const KompassBlocks(
      {super.key,
      required this.blocks,
      this.showResponseLines = false,
      this.showChoices = true,
      this.redundantParagraphs = const {}});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks.map((block) => _block(context, block)).toList(),
      );

  Widget _block(BuildContext context, Map<String, dynamic> block) {
    switch (block['type']) {
      case 'paragraph':
        if (redundantParagraphs.contains(block['text']))
          return const SizedBox.shrink();
        final instruction = block['style'] == 'instruction';
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: KompassRichText(
              '${block['text'] ?? ''}',
              style: TextStyle(
                  color: kompassInk,
                  fontSize: block['style'] == 'small' ? 14 : 17,
                  fontWeight: instruction ? FontWeight.w600 : FontWeight.normal,
                  height: 1.6),
            ));
      case 'choice':
        if (!showChoices) return const SizedBox.shrink();
        final options =
            (block['options'] as List? ?? const []).map((v) => '$v').toList();
        return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in options)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Icon(Icons.crop_square_rounded,
                                    size: 18, color: kompassMuted)),
                            const SizedBox(width: 9),
                            Expanded(
                                child: Text(option,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        color: kompassInk,
                                        height: 1.5))),
                          ])),
              ],
            ));
      case 'table':
        final rows = (block['rows'] as List? ?? const [])
            .map((r) => (r as List).map((c) => '$c').toList())
            .toList();
        final headers =
            (block['headers'] as List? ?? const []).map((v) => '$v').toList();
        final all = [if (headers.isNotEmpty) headers, ...rows];
        if (all.isEmpty) return const SizedBox.shrink();
        final columns =
            all.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
        return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minWidth = columns * 105.0;
                final width = constraints.maxWidth > minWidth
                    ? constraints.maxWidth
                    : minWidth;
                return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Table(
                        border: TableBorder.all(color: const Color(0xFFC7D3DF)),
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          for (var i = 0; i < all.length; i++)
                            TableRow(
                              decoration: BoxDecoration(
                                  color: i == 0 && headers.isNotEmpty
                                      ? const Color(0xFFE8EFF6)
                                      : Colors.white),
                              children: [
                                for (var j = 0; j < columns; j++)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 12),
                                    child: SelectableText(
                                        j < all[i].length ? all[i][j] : '',
                                        style: TextStyle(
                                            color: kompassInk,
                                            fontSize: 15,
                                            height: 1.4,
                                            fontWeight:
                                                i == 0 && headers.isNotEmpty
                                                    ? FontWeight.bold
                                                    : FontWeight.normal)),
                                  )
                              ],
                            )
                        ],
                      ),
                    ));
              },
            ));
      case 'response':
        if (!showResponseLines) return const SizedBox.shrink();
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (block['label'] != null)
                  Text('${block['label']}',
                      style: const TextStyle(color: kompassInk)),
                for (var i = 0;
                    i < ((block['lines'] as num?)?.toInt() ?? 1).clamp(1, 8);
                    i++)
                  Container(
                      height: 30,
                      decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Color(0xFFABBBCB))))),
                if (block['unit'] != null)
                  Text('${block['unit']}',
                      style: const TextStyle(color: kompassMuted)),
              ],
            ));
      case 'space':
        return const SizedBox(height: 8);
      default:
        final alternate = block['alt'] ?? block['text'];
        return alternate == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('$alternate',
                    style: const TextStyle(color: kompassInk, height: 1.5)));
    }
  }
}

class KompassPassage extends StatelessWidget {
  final KompassStimulus stimulus;
  final String? selectedLine;
  final ValueChanged<String>? onLineSelected;
  const KompassPassage(
      {super.key,
      required this.stimulus,
      this.selectedLine,
      this.onLineSelected});
  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    return KompassCard(
        color: const Color(0xFFFFFEF9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.menu_book_rounded, color: kompassMuted),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(stimulus.title.isEmpty ? s.text : stimulus.title,
                      style: const TextStyle(
                          color: kompassInk,
                          fontSize: 21,
                          fontWeight: FontWeight.bold)))
            ]),
            const SizedBox(height: 8),
            Text(
                s.choose('Die Zeilennummern bleiben auch beim Umbruch gleich.',
                    'Line numbers stay the same when the text wraps.'),
                style: const TextStyle(color: kompassMuted, fontSize: 12)),
            const SizedBox(height: 18),
            if (stimulus.lines.isEmpty) KompassBlocks(blocks: stimulus.blocks),
            for (final line in stimulus.lines)
              Semantics(
                label: s.choose('Zeile ${line.label}', 'Line ${line.label}'),
                selected: selectedLine == line.id,
                child: Material(
                  color: selectedLine == line.id
                      ? const Color(0xFFDDEFEA)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: onLineSelected == null
                        ? null
                        : () => onLineSelected!(line.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 34,
                                  child: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(line.label,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                              color: kompassMuted,
                                              fontSize: 12)))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: SelectableText(line.text,
                                      style: const TextStyle(
                                          color: kompassInk,
                                          fontSize: 17,
                                          height: 1.6))),
                            ])),
                  ),
                ),
              ),
            if (stimulus.lines.isNotEmpty &&
                stimulus.blocks.any((b) => b['type'] == 'table')) ...[
              const SizedBox(height: 16),
              KompassBlocks(
                  blocks: stimulus.blocks
                      .where((b) => b['type'] == 'table')
                      .toList()),
            ],
          ],
        ));
  }
}

/// Small allowlist for emphasis already authored in the source worksheets.
/// This does not interpret links, scripts, arbitrary HTML or layout markup.
class KompassRichText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const KompassRichText(this.text, {super.key, this.style});

  static TextSpan span(String source, TextStyle? base) {
    final children = <InlineSpan>[];
    var bold = 0, italic = 0, underline = 0, offset = 0;
    final tags =
        RegExp(r'<(/?)(b|strong|i|em|u|br)\s*/?>', caseSensitive: false);
    String decode(String text) => text
        .replaceAll('&nbsp;', '\u00a0')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
    void append(String value) {
      if (value.isEmpty) return;
      children.add(TextSpan(
          text: decode(value),
          style: TextStyle(
            fontWeight: bold > 0 ? FontWeight.bold : null,
            fontStyle: italic > 0 ? FontStyle.italic : null,
            decoration: underline > 0 ? TextDecoration.underline : null,
          )));
    }

    for (final match in tags.allMatches(source)) {
      append(source.substring(offset, match.start));
      final closing = match.group(1) == '/';
      final tag = match.group(2)!.toLowerCase();
      final change = closing ? -1 : 1;
      if (tag == 'b' || tag == 'strong') bold = (bold + change).clamp(0, 100);
      if (tag == 'i' || tag == 'em') italic = (italic + change).clamp(0, 100);
      if (tag == 'u') underline = (underline + change).clamp(0, 100);
      if (tag == 'br') append('\n');
      offset = match.end;
    }
    append(source.substring(offset));
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(span(text, style));
}
