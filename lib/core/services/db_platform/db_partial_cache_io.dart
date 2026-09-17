import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'db_partial_cache.dart';

DbPartialCache createDbPartialCache() => FileDbPartialCache();

class FileDbPartialCache extends DbPartialCache {
  FileDbPartialCache({this.baseDirectory});
  final Directory? baseDirectory;

  Future<File> _file(String key) async {
    final base = baseDirectory ??
        Directory(
            '${(await getApplicationSupportDirectory()).path}/db-downloads');
    await base.create(recursive: true);
    return File('${base.path}/$key.partial');
  }

  @override
  Future<Uint8List?> readRecord(String key) async {
    try {
      final file = await _file(key);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  /// Write to a sibling and rename, so an interrupted checkpoint leaves the
  /// previous record intact rather than a half-written one.
  @override
  Future<void> writeRecord(String key, List<int> raw) async {
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(raw, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> deleteRecord(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }
}
