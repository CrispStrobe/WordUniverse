// lib/features/games/models/word_find_models.dart
import 'package:flutter/foundation.dart';

/// Represents a single cell in the grid (row, col).
@immutable
class GridPosition {
  final int row;
  final int col;

  const GridPosition(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridPosition &&
          runtimeType == other.runtimeType &&
          row == other.row &&
          col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  @override
  String toString() => '($row, $col)';
}

/// Stores information about a word placed in the grid.
class PlacedWord {
  final String word;
  final GridPosition start;
  final GridPosition end;

  PlacedWord({required this.word, required this.start, required this.end});

  /// Checks if a given selection (from start to end) matches this word.
  bool matches(GridPosition selStart, GridPosition selEnd, List<List<String>> grid) {
    // Check forward
    if (selStart == start && selEnd == end) {
      return true;
    }
    // Check backward
    if (selStart == end && selEnd == start) {
      return true;
    }
    return false;
  }
}

/// The result object from the word search generator.
class GridGenerationResult {
  final List<List<String>> grid;
  final List<PlacedWord> placedWords;

  GridGenerationResult({required this.grid, required this.placedWords});
}