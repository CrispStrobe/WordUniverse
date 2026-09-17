import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'db_partial_cache.dart';

DbPartialCache createDbPartialCache() => FileDbPartialCache();

class FileDbPartialCache extends DbPartialCache {
  FileDbPartialCache({this.baseDirectory});
  final Directory? baseDirectory;
  Future<File> _file(String url) async {
    final base = baseDirectory ??
        Directory(
            '${(await getApplicationSupportDirectory()).path}/db-downloads');
    await base.create(recursive: true);
    return File('${base.path}/${keyFor(url)}.partial');
  }

  @override
  Future<Uint8List?> load(String url) async {
    try {
      final file = await _file(url);
      return await file.exists()
          ? decodeDbPartial(await file.readAsBytes())
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String url, List<int> bytes) async {
    final file = await _file(url);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(encodeDbPartial(bytes), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear(String url) async {
    final file = await _file(url);
    if (await file.exists()) await file.delete();
  }
}
