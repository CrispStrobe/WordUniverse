// Decompression and hashing on the Dart VM, for comparison with the browser
// numbers in db_gzip_web.dart.
//
//   dart run tools/bench/gzip_benchmark.dart <pack.db.gz>
//
// The point of this one is the negative result: on the VM these are compiled
// to machine code and are fast enough, which is why only the web path was
// moved onto native primitives.
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final compressed = File(args.first).readAsBytesSync();

  var watch = Stopwatch()..start();
  final viaArchive = GZipDecoder().decodeBytes(compressed, verify: true);
  final archiveMs = watch.elapsedMilliseconds;

  watch = Stopwatch()..start();
  final crc = getCrc32(viaArchive);
  final crcMs = watch.elapsedMilliseconds;

  watch = Stopwatch()..start();
  final viaIo = gzip.decode(compressed);
  final ioMs = watch.elapsedMilliseconds;

  watch = Stopwatch()..start();
  sha256.convert(viaIo);
  final shaMs = watch.elapsedMilliseconds;

  if (viaIo.length != viaArchive.length) throw StateError('mismatch');
  final trailer = ByteData.sublistView(compressed, compressed.length - 8);
  if (trailer.getUint32(0, Endian.little) != crc) throw StateError('crc');

  print('${compressed.length ~/ 1048576} MB gz -> ${viaIo.length ~/ 1048576} MB');
  print('  gunzip  package:archive (verify:true)  $archiveMs ms');
  print('  crc32   explicit second pass           $crcMs ms');
  print('  gunzip  dart:io gzip.decode            $ioMs ms');
  print('  sha256  package:crypto                 $shaMs ms');
}
