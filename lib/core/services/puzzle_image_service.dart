// lib/core/services/puzzle_image_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PuzzleImageService {
  static final PuzzleImageService instance = PuzzleImageService._internal();
  factory PuzzleImageService() => instance;
  PuzzleImageService._internal();

  List<String> _puzzleImagePaths = [];

  Future<void> init() async {
    debugPrint("[PuzzleImageService] Initializing...");
    
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      debugPrint("[PuzzleImageService] AssetManifest.json loaded successfully.");

      // --- NEW VERBOSE DEBUGGING ---
      final allAssetKeys = manifestMap.keys.toList();
      debugPrint("==============================================================");
      debugPrint("[PuzzleImageService] ALL ASSETS FOUND IN THE APP BUNDLE:");
      if (allAssetKeys.isEmpty) {
        debugPrint("--> The asset manifest is EMPTY.");
      } else {
        allAssetKeys.forEach(debugPrint);
      }
      debugPrint("==============================================================");
      // --- END VERBOSE DEBUGGING ---

      final puzzleRegex = RegExp(r'assets/images/puzzle\d+\.(png|jpg|jpeg)$');
      
      _puzzleImagePaths = allAssetKeys
          .where((String key) => puzzleRegex.hasMatch(key))
          .toList();
          
      debugPrint("[PuzzleImageService] Found ${_puzzleImagePaths.length} puzzle images after filtering.");

      if (_puzzleImagePaths.isNotEmpty) {
        _puzzleImagePaths.sort();
        debugPrint("[PuzzleImageService] Sorted image paths found: $_puzzleImagePaths");
      } else {
        debugPrint("[PuzzleImageService] WARNING: Filtering found NO puzzle images.");
      }
    } catch (e) {
      debugPrint("[PuzzleImageService] CRITICAL ERROR loading AssetManifest.json: $e");
    }
  }

  String? getImageForLevel(int level) {
    if (_puzzleImagePaths.isEmpty) {
      debugPrint("[PuzzleImageService] No images available to serve for level $level.");
      return null;
    }
    
    final index = (level - 1) % _puzzleImagePaths.length;
    final imagePath = _puzzleImagePaths[index];
    debugPrint("[PuzzleImageService] Serving image '$imagePath' for level $level.");
    return imagePath;
  }
}