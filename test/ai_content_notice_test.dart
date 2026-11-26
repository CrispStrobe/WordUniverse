import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/features/games/providers/game_provider.dart';
import 'package:WortUniversum/features/games/widgets/game_ui.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/shared/widgets/ai_content_notice.dart';

class _Scores extends ChangeNotifier implements GameProvider {
  @override
  int get score => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('game disclosure stays reachable on a narrow timed game',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scores = _Scores();
    addTearDown(scores.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<GameProvider>.value(
      value: scores,
      child: MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: Scaffold(
            body: GameUI(
                title: 'Definition quiz',
                level: 1,
                timeLeft: 60,
                onBack: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ActivePackAiContentInfo));
    await tester.pumpAndSettle();
    expect(
        find.text(const AiContentLabels('en').packDisclosure), findsOneWidget);
  });

  testWidgets('pack disclosure is visible in both interface languages',
      (tester) async {
    for (final language in ['en', 'de']) {
      final labels = AiContentLabels(language);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AiLearningContentNotice(language: language))));
      expect(find.text(labels.title), findsOneWidget);
      expect(find.text(labels.packDisclosure), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'item notice distinguishes generated, revised and unknown details',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AiEntryContentNotice(aiContent: {
      'fields': {
        'enrichment.definitions.0': {
          'origin': 'ai_assisted_revision',
          'details_status': 'partial',
          'generation': {'requested_model': 'historically-recorded'},
        },
        'metadata.grade_examples': {
          'origin': 'ai_generated',
          'details_status': 'recorded',
          'generation': {
            'provider_host': 'provider.example',
            'response_model': 'served'
          },
        },
      },
    }))));
    expect(find.textContaining('Definition: AI-assisted revision'),
        findsOneWidget);
    expect(find.textContaining('Requested model: historically-recorded'),
        findsOneWidget);
    expect(find.textContaining('Examples: AI-generated'), findsOneWidget);
    expect(find.textContaining('Response model: served'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AiEntryContentNotice(aiContent: {}))));
    expect(
        find.text(const AiContentLabels('en').unknownDetails), findsOneWidget);
    expect(find.textContaining('Response model:'), findsNothing);
  });
}
