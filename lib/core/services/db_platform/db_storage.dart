// How much room an install has, where the platform can tell us.
//
// A language pack is stored decompressed (~150 MB for German), so "there was
// not enough space" is a realistic outcome that deserves a real message rather
// than a generic write failure. Browsers expose a quota we can check up front;
// dart:io has no portable free-space API, so on native the check is skipped
// (null) and the loaders translate an out-of-space write instead.
export 'db_storage_stub.dart'
    if (dart.library.io) 'db_storage_io.dart'
    if (dart.library.js_interop) 'db_storage_web.dart';
