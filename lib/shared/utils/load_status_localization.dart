import 'package:intl/intl.dart';
import '../../core/models/load_status.dart';
import '../../generated/l10n.dart';

extension LocalizedLoadStatus on LoadStatus {
  String localized(S s) {
    String mb(int n) =>
        NumberFormat('0.0', s.localeName).format(n / (1024 * 1024));
    String number(int n) => NumberFormat.decimalPattern(s.localeName).format(n);
    return switch (stage) {
      LoadStage.preparing => s.loadPreparing,
      LoadStage.webEngine => s.loadWebEngine,
      LoadStage.locatingStorage => s.loadLocatingStorage,
      LoadStage.checkingDatabase => s.loadCheckingDatabase,
      LoadStage.preparingStorage => s.loadPreparingStorage,
      LoadStage.loadingCompressed => s.loadLoadingCompressed,
      LoadStage.loadedCompressed => s.loadLoadedCompressed(mb(bytes)),
      LoadStage.decompressing => s.loadDecompressing,
      LoadStage.decompressed => s.loadDecompressed(mb(bytes)),
      LoadStage.writingBrowserStorage => s.loadWritingBrowserStorage,
      LoadStage.writingStorage => s.loadWritingStorage,
      LoadStage.savedBrowser => s.loadSavedBrowser,
      LoadStage.savedDisk => s.loadSavedDisk,
      LoadStage.openingDatabase => s.loadOpeningDatabase,
      LoadStage.databaseReady => s.loadDatabaseReady,
      LoadStage.databaseReadyWords => s.loadDatabaseReadyWords(number(count)),
      LoadStage.verifying => s.loadVerifying,
      LoadStage.verifiedWords => s.loadVerifiedWords(number(count)),
      LoadStage.loadingWords => s.loadLoadingWords,
      LoadStage.loadingCustomizations => s.loadLoadingCustomizations,
      LoadStage.ready => s.loadReady,
      LoadStage.downloading => s.loadDownloading,
      LoadStage.downloadBytes => s.loadDownloadBytes(mb(bytes)),
      LoadStage.downloadTotal => s.loadDownloadTotal(mb(bytes), mb(total)),
      LoadStage.downloadComplete => s.loadDownloadComplete(mb(bytes)),
      LoadStage.retrying =>
        s.loadRetrying(number(attempt), number(maxAttempts)),
      LoadStage.paused => s.loadPaused,
      LoadStage.resumeReady => s.loadResumeReady,
      LoadStage.failed => s.loadFailed,
      LoadStage.decompressionFailed => s.loadDecompressionFailed,
      LoadStage.loadingProgress => s.loadLoadingProgress,
      LoadStage.loadingLearning => s.loadLoadingLearning,
      LoadStage.loadingProfile => s.loadLoadingProfile,
      LoadStage.preparingStation => s.preparingSpaceStation,
      LoadStage.preparingMission => s.preparingMission,
      LoadStage.calibrating => s.calibratingNav,
      LoadStage.readyForLaunch => s.readyForLaunch,
    };
  }
}
