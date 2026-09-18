import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:WortUniversum/core/models/language_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/pack_failure_logger.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Cached logger futures belong to the previous widget test's fake-async
    // zone. Reset them with preferences so the next install can finish logging.
    PackFailureLogger.instance.resetForTests();
  });
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
        final pack = kLanguagePacks['de']!;
        // Independent of requiredFreeSizeLabel: one database on either platform
        // (web writes in place, native renames staging), plus headroom for one
        // compressed download.
        final budget =
            pack.expectedDecompressedBytes! + pack.expectedCompressedBytes!;
        expect(texts, contains('${(budget / (1024 * 1024)).round()} MiB'));
        expect(texts, contains(locale == 'en' ? 'temporary' : 'temporär'));
        expect(texts, contains(locale == 'en' ? 'free' : 'frei'));
      });
    }
  }
}
