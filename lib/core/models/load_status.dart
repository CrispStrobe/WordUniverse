/// Locale-independent progress. Services emit data; widgets translate at build
/// time, so an in-flight operation also follows interface-language changes.
enum LoadStage {
  preparing,
  webEngine,
  locatingStorage,
  checkingDatabase,
  preparingStorage,
  loadingCompressed,
  loadedCompressed,
  decompressing,
  decompressed,
  writingBrowserStorage,
  writingStorage,
  savedBrowser,
  savedDisk,
  openingDatabase,
  databaseReady,
  databaseReadyWords,
  verifying,
  verifiedWords,
  loadingWords,
  loadingCustomizations,
  ready,
  downloading,
  downloadBytes,
  downloadTotal,
  downloadComplete,
  retrying,
  paused,
  resumeReady,
  failed,
  decompressionFailed,
  loadingProgress,
  loadingLearning,
  loadingProfile,
  preparingStation,
  preparingMission,
  calibrating,
  readyForLaunch,
}

class LoadStatus {
  const LoadStatus(this.stage,
      {this.bytes = 0,
      this.total = 0,
      this.count = 0,
      this.attempt = 0,
      this.maxAttempts = 0});
  final LoadStage stage;
  final int bytes;
  final int total;
  final int count;
  final int attempt;
  final int maxAttempts;
}

typedef LoadProgress = void Function(double progress, LoadStatus status);
