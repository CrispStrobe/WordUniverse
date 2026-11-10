import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../models/kompass_models.dart';
import '../services/kompass_course_service.dart';
import '../services/kompass_progress_service.dart';
import '../widgets/kompass_blocks.dart';
import '../widgets/kompass_part_input.dart';
import '../widgets/kompass_review_sheet.dart';
import '../widgets/kompass_strings.dart';
import '../widgets/kompass_ui.dart';
import 'kompass_report_screen.dart';

class KompassPlayerScreen extends StatefulWidget {
  final List<String> taskIds;
  final String mode, title;
  final int? timeLimitSeconds;
  final Map<String, dynamic>? session;
  const KompassPlayerScreen(
      {super.key,
      required this.taskIds,
      this.mode = 'practice',
      this.title = 'Kompass 4',
      this.timeLimitSeconds})
      : session = null;
  KompassPlayerScreen.resume(Map<String, dynamic> draft, {super.key})
      : session = draft,
        taskIds = List<String>.from(draft['taskIds'] as List? ?? const []),
        mode = draft['mode'] as String? ?? 'practice',
        title = draft['title'] as String? ?? 'Kompass 4',
        timeLimitSeconds = (draft['timeLimitSeconds'] as num?)?.toInt();
  @override
  State<KompassPlayerScreen> createState() => _KompassPlayerScreenState();
}

class _KompassPlayerScreenState extends State<KompassPlayerScreen>
    with WidgetsBindingObserver {
  final Map<String, Map<String, dynamic>> _answers = {};
  final Map<String, Set<String>> _assistance = {};
  final Map<String, String> _attemptIds = {};
  final Map<String, int> _elapsed = {};
  final Set<String> _skipped = {};
  final Set<String> _seenStimuli = {};
  final Map<String, int> _hintCounts = {};
  final ScrollController _taskScroll = ScrollController();
  late KompassProgressService _progress;
  late String _sessionId;
  KompassCourse? _course;
  List<KompassTask> _tasks = [];
  FlutterTts? _tts;
  DateTime? _deadline, _enteredAt;
  Timer? _ticker, _saveDebounce;
  int _index = 0, _secondsLeft = 0;
  bool _ready = false, _busy = false, _completed = false, _timedOut = false;
  bool _incompatible = false, _speaking = false, _finishPromptOpen = false;
  String? _error;
  bool get _supported => widget.mode == 'practice' || widget.mode == 'paper';
  bool get _practice => widget.mode == 'practice';
  KompassTask get _task => _tasks[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    _progress = context.read<KompassProgressService>();
    _sessionId = widget.session?['sessionId'] as String? ??
        '${DateTime.now().microsecondsSinceEpoch}-${_progress.attempts.length}';
    final courses = context.read<KompassCourseService>();
    await courses.load();
    if (!mounted) return;
    _course = courses.course;
    if (_course == null) {
      setState(() => _ready = true);
      return;
    }
    _tasks =
        widget.taskIds.map(_course!.taskById).whereType<KompassTask>().toList();
    final draft = widget.session;
    if (draft != null) {
      _incompatible = draft['courseId'] != _course!.id ||
          draft['courseVersion'] != _course!.version ||
          (draft['courseFingerprint'] != null &&
              draft['courseFingerprint'] != _course!.fingerprint) ||
          _tasks.length != widget.taskIds.length;
      if (!_incompatible) {
        _index = ((draft['index'] as num?)?.toInt() ?? 0)
            .clamp(0, _tasks.isEmpty ? 0 : _tasks.length - 1);
        for (final entry
            in Map<String, dynamic>.from(draft['answers'] as Map? ?? {})
                .entries) {
          _answers[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
        for (final entry
            in Map<String, dynamic>.from(draft['assistance'] as Map? ?? {})
                .entries) {
          _assistance[entry.key] = Set<String>.from(entry.value as List);
        }
        _attemptIds.addAll(
            Map<String, String>.from(draft['attemptIds'] as Map? ?? {}));
        for (final entry
            in Map<String, dynamic>.from(draft['elapsed'] as Map? ?? {})
                .entries) {
          _elapsed[entry.key] = (entry.value as num).toInt();
        }
        for (final entry
            in Map<String, dynamic>.from(draft['hintCounts'] as Map? ?? {})
                .entries) {
          _hintCounts[entry.key] = (entry.value as num).toInt();
        }
        _skipped.addAll(List<String>.from(draft['skipped'] as List? ?? []));
        _seenStimuli
            .addAll(List<String>.from(draft['seenStimuli'] as List? ?? []));
        _deadline = DateTime.tryParse('${draft['deadline'] ?? ''}');
      }
    }
    if (_incompatible) {
      setState(() => _ready = true);
      return;
    }
    if (_deadline == null && widget.timeLimitSeconds != null) {
      _deadline =
          DateTime.now().add(Duration(seconds: widget.timeLimitSeconds!));
    }
    _enteredAt = DateTime.now();
    _refreshClock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _completed) return;
      _refreshClock();
      if (_deadline != null) setState(() {});
      if (_deadline != null && _secondsLeft <= 0 && !_busy) {
        _finish(confirm: false, timedOut: true);
      }
    });
    setState(() => _ready = true);
    await _persist();
  }

  void _refreshClock() {
    _secondsLeft = _deadline == null
        ? 0
        : _deadline!.difference(DateTime.now()).inSeconds.clamp(0, 86400);
  }

  void _clockCurrent() {
    if (!_ready ||
        _tasks.isEmpty ||
        _enteredAt == null ||
        _completed ||
        _incompatible) return;
    _elapsed[_task.id] = (_elapsed[_task.id] ?? 0) +
        DateTime.now().difference(_enteredAt!).inSeconds;
    _enteredAt = DateTime.now();
  }

  Future<void> _persist() async {
    if (!_ready ||
        _completed ||
        _incompatible ||
        _course == null ||
        _tasks.isEmpty) return;
    _clockCurrent();
    await _progress.saveSession({
      'schemaVersion': 1,
      'courseId': _course!.id,
      'courseVersion': _course!.version,
      'courseFingerprint': _course!.fingerprint,
      'sessionId': _sessionId,
      'taskIds': widget.taskIds,
      'mode': widget.mode,
      'title': widget.title,
      'timeLimitSeconds': widget.timeLimitSeconds,
      'deadline': _deadline?.toIso8601String(),
      'index': _index,
      'answers': _answers,
      'assistance': {
        for (final e in _assistance.entries) e.key: e.value.toList()
      },
      'attemptIds': _attemptIds,
      'elapsed': _elapsed,
      'hintCounts': _hintCounts,
      'skipped': _skipped.toList(),
      'seenStimuli': _seenStimuli.toList(),
    }, course: _course);
  }

  void _change(String partId, dynamic value) {
    setState(() {
      _answers.putIfAbsent(_task.id, () => {})[partId] = value;
      _skipped.remove(_task.id);
      _error = null;
    });
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _persist);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _persist();
      _tts?.stop();
      _speaking = false;
    } else if (_ready && !_completed) {
      _enteredAt = DateTime.now();
      _refreshClock();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _ticker?.cancel();
    if (_ready && !_completed) _persist();
    _tts?.stop();
    _taskScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = KompassStrings.of(context);
    // Review changes from the sheet update feedback without regrading answers.
    context.watch<KompassProgressService>();
    if (!_ready)
      return KompassPage(
          title: widget.title,
          child: const Center(child: CircularProgressIndicator()));
    if (_incompatible)
      return KompassPage(
          title: widget.title,
          child: KompassEmpty(
              title: s.choose(
                  'Dieser Zwischenstand gehört zu einer älteren Kursversion',
                  'This draft belongs to a different course version'),
              message: s.choose(
                  'Deine bewerteten Versuche bleiben erhalten. Kehre zum Kurs zurück und beginne eine neue Runde.',
                  'Your assessed attempts are preserved. Return to the course and begin a new session.'),
              action: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.back))));
    if (_course == null || _tasks.isEmpty)
      return KompassPage(
          title: widget.title,
          child: KompassEmpty(
              title: s.choose('Keine Aufgaben verfügbar', 'No tasks available'),
              message: s.choose(
                  'Kehre zum Kurs zurück und wähle eine neue Runde.',
                  'Return to the course and choose a new session.'),
              action: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.back))));
    if (_completed) return _summary(context);
    final stimulus = _course!.stimulusById(_task.stimulusId);
    final attempt = _currentAttempt();
    return KompassPage(
        title: widget.title,
        actions: [
          if (stimulus != null)
            IconButton(
                tooltip: s.text,
                icon: const Icon(Icons.menu_book_rounded),
                onPressed: () => _showPassage(context, stimulus)),
          IconButton(
              tooltip: s.choose('Runde beenden', 'End session'),
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _busy ? null : () => _finish()),
        ],
        child: Column(children: [
          _status(context),
          Expanded(child: LayoutBuilder(builder: (context, c) {
            final desktop = stimulus != null && c.maxWidth >= 960;
            final taskPane = SingleChildScrollView(
              controller: _taskScroll,
              padding: EdgeInsets.all(c.maxWidth < 600 ? 14 : 22),
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!desktop && stimulus != null) ...[
                          KompassCard(
                              padding: EdgeInsets.zero,
                              child: ExpansionTile(
                                key: PageStorageKey('passage-${stimulus.id}'),
                                initiallyExpanded:
                                    !_seenStimuli.contains(stimulus.id),
                                maintainState: true,
                                onExpansionChanged: (open) {
                                  if (open) _seenStimuli.add(stimulus.id);
                                },
                                leading: const Icon(Icons.menu_book_rounded),
                                title: Text(stimulus.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: kompassInk)),
                                subtitle: Text(s.choose(
                                    'Lesetext jederzeit öffnen',
                                    'Open the reading text at any time')),
                                children: [KompassPassage(stimulus: stimulus)],
                              )),
                          const SizedBox(height: 16),
                        ],
                        _taskCard(context, stimulus, attempt),
                        if (_supported && attempt == null) ...[
                          const SizedBox(height: 16),
                          _support(context)
                        ],
                        if (attempt != null && _practice) ...[
                          const SizedBox(height: 16),
                          _feedback(context, _task, attempt),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          KompassNotice(
                              text: _error!, color: const Color(0xFFFFEFCE))
                        ],
                        if (_progress.storageError != null) ...[
                          const SizedBox(height: 14),
                          KompassNotice(
                              text: s.storageWarning,
                              color: const Color(0xFFFFEFCE))
                        ],
                        const SizedBox(height: 14),
                        if (attempt == null)
                          Wrap(spacing: 10, runSpacing: 6, children: [
                            TextButton.icon(
                                onPressed: _busy ? null : _skip,
                                icon: const Icon(Icons.skip_next_rounded),
                                label: Text(s.skip)),
                            TextButton.icon(
                                onPressed: _busy ? null : _notTaught,
                                icon: const Icon(Icons.school_outlined),
                                label: Text(s.notTaught)),
                          ]),
                      ],
                    ),
                  )),
            );
            if (!desktop) return taskPane;
            return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 22, 0, 22),
                          child: KompassPassage(stimulus: stimulus))),
                  Expanded(flex: 6, child: taskPane),
                ]);
          })),
          _navigation(context, attempt),
        ]));
  }

  Widget _status(BuildContext context) {
    final s = KompassStrings.of(context);
    return Container(
        color: Colors.white,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 20,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                      s.choose('Aufgabe ${_index + 1} von ${_tasks.length}',
                          'Task ${_index + 1} of ${_tasks.length}'),
                      style: const TextStyle(
                          color: kompassInk, fontWeight: FontWeight.bold)),
                  KompassBadge(
                      label: s.mode(widget.mode),
                      icon: _supported
                          ? Icons.lightbulb_outline_rounded
                          : Icons.person_outline_rounded),
                  if (_deadline != null)
                    Semantics(
                        liveRegion: _secondsLeft <= 60,
                        child: Text(
                            '${s.choose('Verbleibend', 'Remaining')} ${kompassDuration(_secondsLeft)}',
                            style: TextStyle(
                                color: _secondsLeft <= 300
                                    ? const Color(0xFF9C3F20)
                                    : kompassMuted,
                                fontWeight: FontWeight.bold))),
                ],
              )),
          LinearProgressIndicator(
              value: (_index + 1) / _tasks.length,
              minHeight: 3,
              backgroundColor: const Color(0xFFE2EAF2),
              color: const Color(0xFF378C7A)),
        ]));
  }

  Widget _taskCard(BuildContext context, KompassStimulus? stimulus,
      KompassAttempt? attempt) {
    final s = KompassStrings.of(context);
    return KompassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        KompassBadge(
            label: s.domain(_task.domain),
            icon: kompassDomainIcon(_task.domain),
            color: kompassDomainColor(_task.domain)),
        KompassBadge(
            label: '${kompassPoints(_task.points)} ${s.points}',
            color: const Color(0xFFEDF1F5)),
      ]),
      const SizedBox(height: 16),
      Text(_task.title,
          style: const TextStyle(
              color: kompassInk,
              fontWeight: FontWeight.bold,
              fontSize: 25,
              height: 1.3)),
      const SizedBox(height: 20),
      KompassBlocks(
          blocks: _task.screenBlocks,
          showChoices: false,
          redundantParagraphs: _task.parts.map((p) => p.prompt).toSet()),
      const Divider(height: 30),
      if (!_supported)
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
                s.choose('Rückmeldung erhältst du am Ende der Runde.',
                    'Feedback is available at the end of the session.'),
                style: const TextStyle(color: kompassMuted, fontSize: 13))),
      ..._responseInputs(stimulus, attempt),
    ]));
  }

  List<Widget> _responseInputs(
      KompassStimulus? stimulus, KompassAttempt? attempt) {
    final seenGroups = <String>{};
    final inputs = <Widget>[];
    for (final part in _task.parts) {
      final group = part.metadata['responseGroupId'] as String?;
      if (group != null && !seenGroups.add(group)) continue;
      final grouped = group == null
          ? [part]
          : _task.parts
              .where((p) => p.metadata['responseGroupId'] == group)
              .toList();
      final displayPart = group == null
          ? part
          : KompassPart.fromJson({
              ...part.metadata,
              'prompt': part.metadata['responseGroupPrompt'] ?? part.prompt,
            });
      inputs.add(KompassPartInput(
        key: ValueKey('${_task.id}/${group ?? part.id}'),
        part: displayPart,
        value: _answers[_task.id]?[part.id],
        stimulus: stimulus,
        enabled: !_busy && attempt == null,
        onChanged: (value) {
          for (final target in grouped) {
            _change(target.id, value);
          }
        },
      ));
    }
    return inputs;
  }

  Widget _support(BuildContext context) {
    final s = KompassStrings.of(context);
    final used = _assistance[_task.id] ?? <String>{};
    final shown = _hintCounts[_task.id] ?? 0;
    return KompassCard(
        color: const Color(0xFFEAF2F6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                s.choose(
                    'Hilfe gehört zum Lernen', 'Support is part of learning'),
                style: const TextStyle(
                    color: kompassInk,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 7),
            Text(
                s.choose(
                    'Wenn du Hilfe nutzt, wird dieser Versuch als unterstützt gespeichert.',
                    'Using help records this attempt as supported.'),
                style: const TextStyle(
                    color: kompassMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_task.hints.isNotEmpty)
                OutlinedButton.icon(
                    onPressed: shown >= _task.hints.length
                        ? null
                        : () {
                            _assistance
                                .putIfAbsent(_task.id, () => {})
                                .add('hint');
                            setState(() => _hintCounts[_task.id] = shown + 1);
                            _persist();
                          },
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: Text(s.choose(
                        'Tipp ${shown + 1 > _task.hints.length ? shown : shown + 1}',
                        'Hint ${shown + 1 > _task.hints.length ? shown : shown + 1}'))),
              OutlinedButton.icon(
                  onPressed: _readAloud,
                  icon: Icon(_speaking
                      ? Icons.stop_rounded
                      : Icons.volume_up_outlined),
                  label: Text(_speaking
                      ? s.choose('Vorlesen stoppen', 'Stop reading')
                      : s.choose('Vorlesen lassen', 'Read aloud'))),
              FilterChip(
                  selected: used.contains('adultHelp'),
                  label:
                      Text(s.choose('Jemand hat geholfen', 'Someone helped')),
                  onSelected: used.contains('adultHelp')
                      ? null
                      : (_) {
                          setState(() => _assistance
                              .putIfAbsent(_task.id, () => {})
                              .add('adultHelp'));
                          _persist();
                        }),
            ]),
            for (var i = 0; i < shown && i < _task.hints.length; i++)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: KompassNotice(
                      text: _task.hints[i],
                      icon: Icons.lightbulb_outline_rounded,
                      color: const Color(0xFFFFF5D9))),
          ],
        ));
  }

  Widget _navigation(BuildContext context, KompassAttempt? attempt) {
    final s = KompassStrings.of(context);
    final last = _index == _tasks.length - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFD8E2EC)))),
      child: Row(children: [
        IconButton(
            tooltip: s.back,
            onPressed: _index == 0 || _busy ? null : () => _move(_index - 1),
            icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
                _progress.storageError == null
                    ? s.saved
                    : s.choose('Speichern noch offen', 'Save pending'),
                style: const TextStyle(color: kompassMuted, fontSize: 11))),
        const SizedBox(width: 8),
        Flexible(
            flex: 2,
            child: FilledButton.icon(
              key: const ValueKey('kompass-player-primary'),
              onPressed: _busy
                  ? null
                  : () {
                      if (_practice && attempt == null) {
                        _submitCurrent();
                      } else if (last) {
                        _finish();
                      } else {
                        _move(_index + 1);
                      }
                    },
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_practice && attempt == null
                      ? Icons.check_rounded
                      : last
                          ? Icons.flag_rounded
                          : Icons.arrow_forward_rounded),
              label: Text(_practice && attempt == null
                  ? s.check
                  : last
                      ? s.finish
                      : s.next),
            )),
      ]),
    );
  }

  KompassAttempt? _currentAttempt() {
    final id = _attemptIds[_task.id];
    if (id == null) return null;
    return _progress.attempts.where((a) => a.id == id).firstOrNull;
  }

  bool _hasAnswer(String taskId) =>
      (_answers[taskId]?.values ?? const []).any((v) => v is String
          ? v.trim().isNotEmpty
          : v is List
              ? v.isNotEmpty
              : v != null);

  Future<void> _submitCurrent() async {
    final s = KompassStrings.of(context);
    if (!_hasAnswer(_task.id)) {
      setState(() => _error = s.choose(
          'Gib zuerst eine Antwort ein oder überspringe die Aufgabe.',
          'Enter an answer first, or skip the task.'));
      return;
    }
    setState(() => _busy = true);
    _clockCurrent();
    try {
      final task = _task;
      final result = await _progress.recordAttempt(
          course: _course!,
          task: task,
          answers: _answers[task.id] ?? {},
          mode: widget.mode,
          sessionId: _sessionId,
          assistance: _assistance[task.id] ?? {},
          elapsedSeconds: _elapsed[task.id] ?? 0);
      _attemptIds[task.id] = result.id;
      await _persist();
    } catch (_) {
      _error = s.choose(
          'Die Antwort konnte nicht gespeichert werden. Versuche es erneut.',
          'The answer could not be saved. Please try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _move(int next) async {
    _clockCurrent();
    _tts?.stop();
    if (_task.stimulusId != null) _seenStimuli.add(_task.stimulusId!);
    setState(() {
      _index = next;
      _speaking = false;
      _error = null;
      _enteredAt = DateTime.now();
    });
    if (_taskScroll.hasClients) _taskScroll.jumpTo(0);
    await _persist();
  }

  Future<void> _skip() async {
    _skipped.add(_task.id);
    if (_index < _tasks.length - 1) {
      await _move(_index + 1);
    } else {
      await _finish();
    }
  }

  Future<void> _notTaught() async {
    final s = KompassStrings.of(context);
    final selected = _task.competencyIds.toSet();
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(s.notTaught),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(s.choose(
                          'Welche Fähigkeiten hast du noch nicht gelernt? Du kannst sie im Lernbild wieder einschalten.',
                          'Which skills have you not learned yet? You can include them again in your learning picture.')),
                      for (final id in _task.competencyIds)
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title:
                                Text(_course!.competencyById(id)?.title ?? id),
                            value: selected.contains(id),
                            onChanged: (value) => update(() {
                                  value == true
                                      ? selected.add(id)
                                      : selected.remove(id);
                                })),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.cancel)),
                  FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, true),
                      child: Text(
                          s.choose('Merken und weiter', 'Save and continue')))
                ],
              ),
            ));
    if (confirm != true || !mounted) return;
    for (final id in selected) {
      await _progress.setNotTaught(id, true);
    }
    await _skip();
  }

  Future<void> _finish({bool confirm = true, bool timedOut = false}) async {
    if (_busy || _completed || _finishPromptOpen) return;
    final s = KompassStrings.of(context);
    if (confirm) {
      _finishPromptOpen = true;
      final unattempted = _tasks
          .where((t) =>
              (!_hasAnswer(t.id) || _skipped.contains(t.id)) &&
              !_attemptIds.containsKey(t.id))
          .length;
      final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(s.finish),
                content: Text(s.choose(
                    'Du kannst jetzt deine Rückmeldung ansehen. $unattempted übersprungene oder leere Aufgaben bleiben unbeobachtet.',
                    'You can now see your feedback. $unattempted skipped or unanswered tasks will remain unobserved.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.choose('Weiterarbeiten', 'Keep working'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.finish))
                ],
              ));
      _finishPromptOpen = false;
      if (proceed != true || !mounted) return;
    }
    setState(() => _busy = true);
    _clockCurrent();
    _tts?.stop();
    try {
      for (final task in _tasks) {
        if (_attemptIds.containsKey(task.id) ||
            !_hasAnswer(task.id) ||
            _skipped.contains(task.id)) continue;
        final attempt = await _progress.recordAttempt(
            course: _course!,
            task: task,
            answers: _answers[task.id] ?? {},
            mode: widget.mode,
            sessionId: _sessionId,
            assistance: _assistance[task.id] ?? {},
            elapsedSeconds: _elapsed[task.id] ?? 0);
        _attemptIds[task.id] = attempt.id;
        // A partial completion can resume without duplicating already saved attempts.
        await _persist();
      }
      _saveDebounce?.cancel();
      await _progress.saveSession(null, course: _course);
      if (mounted)
        setState(() {
          _completed = true;
          _timedOut = timedOut;
          _busy = false;
        });
      _ticker?.cancel();
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = s.choose(
              'Die Runde konnte nicht vollständig gespeichert werden. Deine bisherigen Antworten bleiben erhalten.',
              'The session could not be completely saved. Your existing answers are preserved.');
        });
    }
  }

  Future<void> _readAloud() async {
    if (_speaking) {
      await _tts?.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    // Log the request before starting playback; an assisted answer must not
    // silently become independent when a platform interrupts speech.
    _assistance.putIfAbsent(_task.id, () => {}).add('readAloud');
    await _persist();
    try {
      _tts ??= FlutterTts();
      _tts!.setCompletionHandler(() {
        if (mounted) setState(() => _speaking = false);
      });
      await _tts!.setLanguage('de-DE');
      await _tts!.setSpeechRate(.4);
      final stimulus = _course!.stimulusById(_task.stimulusId);
      final words = [
        if (stimulus != null) ...stimulus.lines.map((l) => l.text),
        _task.title,
        ..._task.screenBlocks.where((b) => b['type'] == 'paragraph').map(
            (b) => KompassRichText.span('${b['text']}', null).toPlainText()),
        ..._task.parts.map((p) => p.prompt)
      ].join('. ');
      if (mounted) setState(() => _speaking = true);
      await _tts!.speak(words);
    } catch (_) {
      if (mounted)
        setState(() {
          _speaking = false;
          _error = KompassStrings.of(context).choose(
              'Vorlesen ist auf diesem Gerät gerade nicht verfügbar.',
              'Reading aloud is currently unavailable on this device.');
        });
    }
  }

  void _showPassage(BuildContext context, KompassStimulus stimulus) {
    _seenStimuli.add(stimulus.id);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: KompassPassage(stimulus: stimulus))));
  }

  Widget _feedback(
      BuildContext context, KompassTask task, KompassAttempt attempt) {
    final s = KompassStrings.of(context);
    return KompassCard(
        color: const Color(0xFFE9F4ED),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.choose('Deine Rückmeldung', 'Your feedback'),
                style: const TextStyle(
                    color: kompassInk,
                    fontSize: 21,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            kompassScore(context, attempt.earnedPoints, attempt.possiblePoints,
                pending: attempt.pendingPoints),
            if (attempt.assistance.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      s.choose('Dieser Versuch wurde mit Hilfe bearbeitet.',
                          'This attempt used support.'),
                      style:
                          const TextStyle(color: kompassMuted, fontSize: 13))),
            const SizedBox(height: 14),
            for (final result in attempt.parts)
              Builder(builder: (context) {
                final part =
                    task.parts.firstWhere((p) => p.id == result.partId);
                return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                  result.needsReview
                                      ? Icons.rate_review_outlined
                                      : result.points == result.maxPoints
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.lightbulb_outline_rounded,
                                  color: kompassMuted,
                                  size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      part.prompt.isEmpty
                                          ? part.id
                                          : part.prompt,
                                      style: const TextStyle(
                                          color: kompassInk,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4))),
                            ]),
                        const SizedBox(height: 6),
                        Text(
                            result.needsReview
                                ? s.pending
                                : '${kompassPoints(result.points ?? 0)} / ${kompassPoints(result.maxPoints)} ${s.points}',
                            style: const TextStyle(
                                color: kompassMuted, fontSize: 13)),
                        if (!result.needsReview && part.feedback != null) ...[
                          const SizedBox(height: 6),
                          Text(part.feedback!,
                              style: const TextStyle(
                                  color: kompassInk, height: 1.5))
                        ],
                        if (!result.needsReview && part.answers.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          SelectionArea(
                              child: Text(
                                  '${s.choose('Lösung:', 'Solution:')} ${_solution(part)}',
                                  style: const TextStyle(
                                      color: kompassInk, height: 1.5))),
                        ],
                      ],
                    ));
              }),
            if (attempt.pendingPoints > 0)
              OutlinedButton.icon(
                  onPressed: () => showKompassReview(context, task, attempt),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(s.review)),
          ],
        ));
  }

  String _solution(KompassPart part) {
    final options = {for (final option in part.options) option.id: option.text};
    if (part.type == 'order' ||
        part.type == 'multiChoice' ||
        part.type == 'singleChoice') {
      return part.answers
          .map((id) => options[id] ?? id)
          .join(part.type == 'order' ? ' → ' : ' · ');
    }
    return part.answers.take(3).join(' / ');
  }

  Widget _summary(BuildContext context) {
    final s = KompassStrings.of(context);
    final ids = _attemptIds.values.toSet();
    final attempts =
        _progress.attempts.where((a) => ids.contains(a.id)).toList();
    final earned = attempts.fold<double>(0, (n, a) => n + a.earnedPoints);
    final possible = attempts.fold<double>(0, (n, a) => n + a.possiblePoints);
    final pending = attempts.fold<double>(0, (n, a) => n + a.pendingPoints);
    return KompassPage(
        title: s.choose('Deine Runde', 'Your session'),
        child: SingleChildScrollView(
          key: const ValueKey('kompass-session-summary'),
          padding: const EdgeInsets.all(20),
          child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KompassCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          const Icon(Icons.explore_rounded,
                              size: 52, color: Color(0xFF2B8A75)),
                          const SizedBox(height: 16),
                          Text(
                              _timedOut
                                  ? s.choose('Die Zeit ist um.', 'Time is up.')
                                  : s.choose('Ein Schritt weiter.',
                                      'One step further.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 28,
                                  color: kompassInk,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Text(
                              s.choose(
                                  '${attempts.length} von ${_tasks.length} Aufgaben bearbeitet. ${_tasks.length - attempts.length} Aufgaben bleiben unbeobachtet.',
                                  '${attempts.length} of ${_tasks.length} tasks attempted. ${_tasks.length - attempts.length} tasks remain unobserved.'),
                              style: const TextStyle(
                                  color: kompassMuted, height: 1.5),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Center(
                              child: kompassScore(context, earned, possible,
                                  pending: pending)),
                          const SizedBox(height: 8),
                          Text(
                              s.choose(
                                  'Die Punkte beziehen sich nur auf die bearbeiteten Aufgaben. Offene Rückmeldungen sind noch kein endgültiges Ergebnis.',
                                  'Points cover the tasks you attempted. Pending reviews mean the result is not final.'),
                              style: const TextStyle(
                                  color: kompassMuted,
                                  fontSize: 12,
                                  height: 1.5),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const KompassReportScreen())),
                                    icon: const Icon(Icons.insights_rounded),
                                    label: Text(s.report)),
                                OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(s.choose(
                                        'Zurück zum Kurs', 'Back to course'))),
                              ]),
                        ])),
                    const SizedBox(height: 20),
                    if (_progress.storageError != null) ...[
                      KompassNotice(
                          text: s.storageWarning,
                          color: const Color(0xFFFFEFCE)),
                      const SizedBox(height: 14),
                    ],
                    for (final attempt in attempts)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: ExpansionTile(
                            backgroundColor: Colors.white,
                            collapsedBackgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            collapsedShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: Text(
                                _course!.taskById(attempt.taskId)?.title ??
                                    attempt.taskId,
                                style: const TextStyle(
                                    color: kompassInk,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                kompassScoreLabel(s, attempt.earnedPoints,
                                    attempt.possiblePoints,
                                    pending: attempt.pendingPoints),
                                style: const TextStyle(
                                    color: kompassMuted, fontSize: 13)),
                            children: [
                              _feedback(context,
                                  _course!.taskById(attempt.taskId)!, attempt)
                            ],
                          )),
                  ],
                ),
              )),
        ));
  }
}
