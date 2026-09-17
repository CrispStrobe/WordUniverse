/// Native: dart:io exposes no portable free-space API, and a wrong pre-check is
/// worse than none — an underestimate blocks an install that would have
/// succeeded. Out-of-space is reported accurately at write time instead (see
/// db_platform_mobile.dart, which maps ENOSPC).
Future<int?> availableStorageBytes() async => null;
