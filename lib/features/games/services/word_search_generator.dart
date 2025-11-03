// lib/features/games/logic/word_search_generator.dart
import 'dart:math'; // <-- FIX 1: Was 'dart.math'
import '../models/word_find_models.dart';

/// A static class to handle the generation of word search puzzles.
class WordSearchGenerator {
  // Use a German-specific alphabet, including Umlaute
  // <-- FIX 2: Changed from 'const' to 'final'
  static final List<String> _germanAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ'.split('');
  static final Random _random = Random();

  /// Generates a new word search grid.
  static GridGenerationResult generate(int size, List<String> words) {
    // 1. Initialize an empty grid with nulls
    List<List<String?>> grid =
        List.generate(size, (_) => List.filled(size, null));
    List<PlacedWord> placedWords = [];

    // Sort words from longest to shortest to make placement easier
    words.sort((a, b) => b.length.compareTo(a.length));

    for (String word in words) {
      word = word.toUpperCase();
      bool placed = false;
      int attempts = 0;

      while (!placed && attempts < 50) {
        attempts++;
        // 50% chance for horizontal, 50% for vertical
        bool isHorizontal = _random.nextBool();
        int row = _random.nextInt(size);
        int col = _random.nextInt(size);

        if (_canPlaceWord(grid, word, row, col, isHorizontal)) {
          GridPosition start = GridPosition(row, col);
          GridPosition end;

          if (isHorizontal) {
            for (int i = 0; i < word.length; i++) {
              grid[row][col + i] = word[i];
            }
            end = GridPosition(row, col + word.length - 1);
          } else {
            for (int i = 0; i < word.length; i++) {
              grid[row + i][col] = word[i];
            }
            end = GridPosition(row + word.length - 1, col);
          }
          placedWords.add(PlacedWord(word: word, start: start, end: end));
          placed = true;
        }
      }
      // If a word can't be placed after 50 attempts, we skip it.
    }

    // 3. Fill the remaining null spots with random letters
    List<List<String>> finalGrid = List.generate(size, (r) {
      return List.generate(size, (c) {
        if (grid[r][c] == null) {
          return _germanAlphabet[_random.nextInt(_germanAlphabet.length)];
        }
        return grid[r][c]!;
      });
    });

    return GridGenerationResult(grid: finalGrid, placedWords: placedWords);
  }

  /// Checks if a word can be placed at a specific location without conflicts.
  static bool _canPlaceWord(
      List<List<String?>> grid, String word, int row, int col, bool isHorizontal) {
    int size = grid.length;
    if (isHorizontal) {
      if (col + word.length > size) return false; // Out of bounds
      for (int i = 0; i < word.length; i++) {
        // Check for collision with a *different* letter
        if (grid[row][col + i] != null && grid[row][col + i] != word[i]) {
          return false;
        }
      }
    } else { // Vertical
      if (row + word.length > size) return false; // Out of bounds
      for (int i = 0; i < word.length; i++) {
        // Check for collision with a *different* letter
        if (grid[row + i][col] != null && grid[row + i][col] != word[i]) {
          return false;
        }
      }
    }
    return true;
  }
}