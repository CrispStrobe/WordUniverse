import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/kompass_models.dart';
import '../services/kompass_progress_service.dart';
import 'kompass_strings.dart';
import 'kompass_ui.dart';

Future<void> showKompassReview(
        BuildContext context, KompassTask task, KompassAttempt attempt) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => KompassReviewSheet(task: task, attempt: attempt));

class KompassReviewSheet extends StatefulWidget {
  final KompassTask task;
  final KompassAttempt attempt;
  const KompassReviewSheet(
      {super.key, required this.task, required this.attempt});
  @override
  State<KompassReviewSheet> createState() => _KompassReviewSheetState();
}

class _KompassReviewSheetState extends State<KompassReviewSheet> {
  final Map<String, double> _scores = {};
  String _reviewer = 'self';
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    final pending = widget.attempt.parts.where((p) => p.needsReview).toList();
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
      child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.review,
                      style: const TextStyle(
                          color: kompassInk,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.task.title,
                      style:
                          const TextStyle(color: kompassMuted, fontSize: 17)),
                  const SizedBox(height: 16),
                  KompassNotice(
                      text: s.choose(
                          'Vergleiche die Antwort mit den Kriterien. Sinngemäße Antworten können richtig sein. Wähle nur Punkte, die sich mit den Kriterien begründen lassen. Du kannst die Prüfung auch offen lassen.',
                          'Compare the answer with the rubric. Different wording can still be correct. Award only points supported by the criteria. You may also leave this review pending.')),
                  const SizedBox(height: 16),
                  for (final result in pending) ...[
                    Builder(builder: (context) {
                      final part = widget.task.parts
                          .where((p) => p.id == result.partId)
                          .firstOrNull;
                      final rubric = result.rubric.isNotEmpty
                          ? result.rubric
                          : (part?.rubric ?? const <String>[]);
                      final feedback = result.rubric.isNotEmpty
                          ? result.feedback
                          : part?.feedback;
                      final steps = result.creditSteps.isNotEmpty
                          ? result.creditSteps
                          : (part?.creditSteps ?? [0.0, result.maxPoints]);
                      return KompassCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(
                                result.prompt.isNotEmpty
                                    ? result.prompt
                                    : part?.prompt ?? result.partId,
                                style: const TextStyle(
                                    color: kompassInk,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    height: 1.5)),
                            const SizedBox(height: 12),
                            Text(s.answer,
                                style: const TextStyle(
                                    color: kompassMuted, fontSize: 12)),
                            const SizedBox(height: 5),
                            SelectableText(_response(result.response, s),
                                style: const TextStyle(
                                    color: kompassInk,
                                    fontSize: 17,
                                    height: 1.5)),
                            const Divider(height: 28),
                            for (final criterion in rubric)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(criterion,
                                      style: const TextStyle(
                                          color: kompassInk, height: 1.5))),
                            if (feedback != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(feedback,
                                      style: const TextStyle(
                                          color: kompassMuted, height: 1.5))),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final credit
                                  in steps.toSet().toList()..sort())
                                ChoiceChip(
                                    label: Text(
                                        '${kompassPoints(credit)} / ${kompassPoints(result.maxPoints)} ${s.points}'),
                                    selected: _scores[result.partId] == credit,
                                    onSelected: _saving || rubric.isEmpty
                                        ? null
                                        : (_) => setState(() =>
                                            _scores[result.partId] = credit)),
                            ]),
                          ]));
                    }),
                    const SizedBox(height: 14),
                  ],
                  Text(
                      s.choose('Wer hat die Kriterien geprüft?',
                          'Who reviewed the rubric?'),
                      style: const TextStyle(
                          color: kompassInk, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in {
                      'self': s.choose('Ich selbst', 'Myself'),
                      'parent':
                          s.choose('Gemeinsam zu Hause', 'Together at home'),
                      'teacher': s.choose('Lehrkraft', 'Teacher'),
                    }.entries)
                      ChoiceChip(
                          label: Text(entry.value),
                          selected: _reviewer == entry.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _reviewer = entry.key)),
                  ]),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    KompassNotice(text: _error!, color: const Color(0xFFFFEFCE))
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                      key: const ValueKey('kompass-review-save'),
                      onPressed: _saving ||
                              _scores.length != pending.length ||
                              pending.isEmpty
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.done_all_rounded),
                      label:
                          Text(s.choose('Prüfung speichern', 'Save review'))),
                  TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(s.choose('Später prüfen', 'Review later'))),
                ],
              ),
            ),
          )),
    );
  }

  String _response(dynamic response, KompassStrings s) {
    if (response == null ||
        response == '' ||
        response is List && response.isEmpty) {
      return s.choose('(keine Antwort)', '(no answer)');
    }
    return response is List ? response.join(' · ') : '$response';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context
          .read<KompassProgressService>()
          .reviewAttempt(widget.attempt.id, _scores, reviewer: _reviewer);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = KompassStrings.of(context).choose(
              'Die Prüfung konnte nicht gespeichert werden.',
              'The review could not be saved.');
        });
    }
  }
}
