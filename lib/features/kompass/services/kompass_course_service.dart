import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/kompass_models.dart';

class KompassCourseService extends ChangeNotifier {
  KompassCourseService({AssetBundle? assets}) : _assets = assets ?? rootBundle;
  final AssetBundle _assets;
  KompassCourse? course;
  String? error;
  bool loading = false;
  Future<void>? _pending;

  Future<void> load() {
    if (course != null) return Future.value();
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      course = KompassCourse.decode(
        await _assets.loadString('assets/kompass/bw_de_v1.json'),
      );
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
