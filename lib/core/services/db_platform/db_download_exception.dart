/// Download/install failures shared by transports and durable storage.
class DbDownloadException implements Exception {
  final String message;
  final bool isNetwork;
  DbDownloadException(this.message, {this.isNetwork = false});
  @override
  String toString() => message;
}

/// Storage failures must never trigger network retry/backoff.
class DbStorageException extends DbDownloadException {
  DbStorageException(super.message, {this.errorName, this.cause});
  final String? errorName;
  final Object? cause;
}

class DbInsufficientSpaceException extends DbStorageException {
  DbInsufficientSpaceException(
      {this.requiredBytes, this.availableBytes, super.errorName, super.cause})
      : super('Not enough free space to install the language pack.');
  // A failed checkpoint cannot know the total installation requirement.
  final int? requiredBytes;
  final int? availableBytes;
}
