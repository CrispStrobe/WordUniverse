// lib/core/services/db_platform/db_platform_interface.dart:
import 'package:sqflite/sqflite.dart';

Future<Database> initPlatformDatabase() {
  throw UnsupportedError('Cannot init database: Unknown platform');
}