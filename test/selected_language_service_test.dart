import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/services/language_pack_service.dart';
import 'package:WortUniversum/core/services/vocabulary_service.dart';
import 'package:WortUniversum/core/services/db_platform/db_remote.dart';

class SelectionVocabulary extends VocabularyService {
  String saved = 'de';
  String loaded = 'en';
  bool ready = true;
  Object? failure;
  @override String get learningLanguage => loaded;
  @override bool get isInitialized => ready;
  @override Future<String> savedLearningLanguage() async => saved;
  @override Future<void> rememberLearningLanguage(String code) async { saved = code; }
  @override Future<bool> isPackInstalled(String code) async => code == 'en';
  @override Future<void> setLearningLanguage(String code, {bool allowDownload = false,
    void Function(double, String)? onProgress}) async {
    if (failure != null) throw failure!;
    loaded = code;
    ready = true;
  }
}
void main() {
  test('saved German is not ready when rollback left English loaded', () async {
    final vocab = SelectionVocabulary();
    final service = LanguagePackService(vocab);
    await service.savedLanguageStatus();
    expect(service.isActivePackReady, false);
  });
  test('failed install preserves desired choice rather than loaded language', () async {
    final vocab = SelectionVocabulary()..saved = 'en'..failure = StateError('offline');
    final service = LanguagePackService(vocab);
    expect(await service.install('de'), false);
    expect(vocab.saved, 'de');
    expect(service.isActivePackReady, false);
  });
  test('pause is not failure and refresh preserves paused checkpoint UI', () async {
    final vocab = SelectionVocabulary()..failure = DbDownloadPausedException();
    final service = LanguagePackService(vocab);
    expect(await service.install('de'), false);
    expect(service.stateFor('de').status.name, 'paused');
    expect(service.stateFor('de').error, isNull);
    await service.refresh();
    expect(service.stateFor('de').status.name, 'paused');
  });
}
