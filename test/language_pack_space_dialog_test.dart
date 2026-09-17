import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/core/models/load_status.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';
import 'package:WortUniversum/generated/l10n.dart';
import 'package:WortUniversum/shared/widgets/language_pack_dialog.dart';

class _Vocabulary extends VocabularyService {
  @override
  Future<String> savedLearningLanguage() async => 'de';
  @override
  Future<bool> isPackInstalled(String code) async => false;
  @override
  Future<void> setLearningLanguage(String code,
      {bool allowDownload = false, LoadProgress? onProgress}) async {
    throw DbInsufficientSpaceException();
  }
}

void main() {
  for (final locale in ['en', 'de']) {
    for (final failed in [false, true]) {
      testWidgets('$locale displays required install space (failed=$failed)',
          (tester) async {
        final service = LanguagePackService(_Vocabulary(),
            freeSpaceProbe: () async => null);
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: service,
            child: MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                home: LanguagePackDialog(
                    languageCode: 'de', skipConsent: failed))));
        await tester.pumpAndSettle();
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ');
        expect(texts, contains('175 MB'));
        expect(texts, contains(locale == 'en' ? 'free' : 'frei'));
      });
    }
  }
}
