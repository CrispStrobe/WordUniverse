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

  /// Reads the fixed header and the file size rather than the whole prefix:
  /// a resume caption must not cost a 12 MB read.
  @override
  Future<int?> cachedLength(String url) async {
    try {
      final file = await _file(keyFor(url));
      if (!await file.exists()) return null;
      final total = await file.length();
      final handle = await file.open();
      try {
        final header = await handle.read(40);
        if (header.length < 40) return null;
        final view = ByteData.sublistView(header);
        if (view.getUint8(0) != 0x44 ||
            view.getUint8(1) != 0x50 ||
            view.getUint8(2) != 2) {
          return null;
        }
        final payloadLength = view.getUint32(4, Endian.little);
        if (total != 40 + view.getUint8(3) + payloadLength) return null;
        return payloadLength;
      } finally {
        await handle.close();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteRecord(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }
}
