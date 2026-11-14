import 'package:flutter/material.dart';
import '../models/kompass_models.dart';
import 'kompass_strings.dart';
import 'kompass_ui.dart';

class KompassPartInput extends StatelessWidget {
  final KompassPart part;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final KompassStimulus? stimulus;
  final bool enabled;

  /// Bumped when the answer changes from outside the field (a line copied
  /// from the text), so the field shows it.
  final int revision;
  const KompassPartInput(
      {super.key,
      required this.part,
      required this.value,
      required this.onChanged,
      this.stimulus,
      this.enabled = true,
      this.revision = 0});
  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (part.prompt.isNotEmpty) ...[
              Text(part.prompt,
                  style: const TextStyle(
                      color: kompassInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      height: 1.5)),
              const SizedBox(height: 10),
            ],
            if (part.type == 'singleChoice')
              ...part.options.map((o) => _option(
                  context, o.id, o.text, value == o.id, () => onChanged(o.id),
                  multiple: false)),
            if (part.type == 'multiChoice') ...[
              Text(
                  s.choose('Wähle die passenden Antworten.',
                      'Choose the matching answers.'),
                  style: const TextStyle(color: kompassMuted, fontSize: 13)),
              const SizedBox(height: 5),
              ...part.options.map((o) => _option(context, o.id, o.text,
                      (value is List ? value as List : const []).contains(o.id),
                      () {
                    final values = List<String>.from(
                        value is List ? value as List : const []);
                    values.contains(o.id)
                        ? values.remove(o.id)
                        : values.add(o.id);
                    onChanged(values);
                  }, multiple: true)),
            ],
            if (part.type == 'evidence') ...[
              Text(
                  s.choose(
                      'Wähle eine Zeile als Beleg. Du kannst jederzeit im Text nachlesen.',
                      'Select a source line as evidence. You can return to the text at any time.'),
                  style: const TextStyle(
                      color: kompassMuted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              if (stimulus != null)
                ...stimulus!.lines.map((line) => _option(
                    context,
                    line.id,
                    '${line.label}  ${line.text}',
                    value == line.id,
                    () => onChanged(line.id),
                    multiple: false)),
            ],
            if (part.type == 'text' || part.type == 'review')
              TextFormField(
                key: ValueKey(
                    '${part.id}-${enabled ? 'edit' : 'locked'}-$revision'),
                initialValue: value is String ? value as String : '',
                enabled: enabled,
                onChanged: onChanged,
                autocorrect: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                spellCheckConfiguration:
                    const SpellCheckConfiguration.disabled(),
                enableIMEPersonalizedLearning: false,
                enableSuggestions: false,
                keyboardType: part.type == 'review'
                    ? TextInputType.multiline
                    : TextInputType.text,
                textCapitalization: TextCapitalization.none,
                minLines: part.type == 'review' ? 3 : 1,
                maxLines: part.type == 'review' ? 7 : 3,
                style: const TextStyle(
                    color: kompassInk, fontSize: 17, height: 1.5),
                decoration: InputDecoration(
                    labelText: s.answer, alignLabelWithHint: true),
              ),
            if (part.type == 'order') _order(context),
          ],
        ));
  }

  Widget _option(BuildContext context, String id, String text, bool selected,
          VoidCallback change,
          {required bool multiple}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          selected: selected,
          enabled: enabled,
          child: Material(
            color: selected ? const Color(0xFFE2F2EC) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('option-${part.id}-$id'),
              onTap: enabled ? change : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF247968)
                            : const Color(0xFFCAD6E2),
                        width: selected ? 2 : 1)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          multiple
                              ? (selected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded)
                              : (selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded),
                          color:
                              selected ? const Color(0xFF247968) : kompassMuted,
                          size: 23),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(text,
                              style: const TextStyle(
                                  color: kompassInk,
                                  fontSize: 16,
                                  height: 1.5))),
                    ]),
              ),
            ),
          ),
        ),
      );

  Widget _order(BuildContext context) {
    final s = KompassStrings.of(context);
    final ids = value is List
        ? List<String>.from(value as List)
        : part.options.map((o) => o.id).toList();
    final options = {for (final option in part.options) option.id: option.text};
    void move(int index, int offset) {
      final target = index + offset;
      if (target < 0 || target >= ids.length) return;
      final next = List<String>.from(ids);
      next.insert(target, next.removeAt(index));
      onChanged(next);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          s.choose(
              'Bringe die Schritte mit den Pfeilen in die richtige Reihenfolge.',
              'Use the arrows to put the steps in the correct order.'),
          style:
              const TextStyle(color: kompassMuted, fontSize: 13, height: 1.4)),
      const SizedBox(height: 8),
      for (var i = 0; i < ids.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding:
                const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 4),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCAD6E2))),
            child: Row(children: [
              SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: kompassMuted))),
              Expanded(
                  child: Text(options[ids[i]] ?? ids[i],
                      style: const TextStyle(
                          color: kompassInk, height: 1.5, fontSize: 16))),
              Column(children: [
                IconButton(
                    tooltip: s.choose('Nach oben', 'Move up'),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    onPressed: enabled && i > 0 ? () => move(i, -1) : null),
                IconButton(
                    tooltip: s.choose('Nach unten', 'Move down'),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: enabled && i < ids.length - 1
                        ? () => move(i, 1)
                        : null),
              ]),
            ]),
          ),
        ),
      if (value is! List)
        OutlinedButton.icon(
            onPressed: enabled ? () => onChanged(ids) : null,
            icon: const Icon(Icons.done_rounded),
            label: Text(
                s.choose('Diese Reihenfolge verwenden', 'Use this order'))),
    ]);
  }
}
