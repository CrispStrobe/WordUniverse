// lib/features/games/services/word_snake_generator.dart
import 'dart:math';

class Point {
  final int x, y;
  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) => other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

class WordSnakeGrid {
  final List<List<String>> grid;
  final String word;
  final List<Point> path;
  final int rows;
  final int cols;

  WordSnakeGrid({
    required this.grid,
    required this.word,
    required this.path,
    required this.rows,
    required this.cols,
  });
}

enum SnakeDifficulty { easy, medium, hard }

class WordSnakeGenerator {
  final Random _random = Random();

  final List<Point> _directions = const [
    Point(1, 0),
    Point(-1, 0),
    Point(0, 1),
    Point(0, -1),
  ];

  WordSnakeGrid? generate(String word, SnakeDifficulty difficulty) {
    word = word.toUpperCase();

    // Get possible grid dimensions based on word length and difficulty
    List<List<int>> dimensions = _getPossibleDimensions(word.length, difficulty);
    dimensions.shuffle(_random);

    // Try many random arrangements
    for (var dim in dimensions) {
      int rows = dim[0];
      int cols = dim[1];

      for (int attempt = 0; attempt < 500; attempt++) {
        var grid = _tryGenerateGrid(word, rows, cols);
        if (grid != null) return grid;
      }
    }

    return null;
  }

  List<List<int>> _getPossibleDimensions(int length, SnakeDifficulty difficulty) {
    List<List<int>> dims = [];

    for (int rows = 2; rows <= length; rows++) {
      if (length % rows == 0) {
        int cols = length ~/ rows;

        bool valid = false;
        switch (difficulty) {
          case SnakeDifficulty.easy:
            valid = (rows == 2 && cols <= 3) || (cols == 2 && rows <= 3);
            break;
          case SnakeDifficulty.medium:
            valid = (rows <= 3 && cols <= 4) || (cols <= 3 && rows <= 4);
            break;
          case SnakeDifficulty.hard:
            valid = (rows <= 4 && cols <= 4);
            break;
        }

        if (valid) {
          dims.add([rows, cols]);
        }
      }
    }

    return dims;
  }

  WordSnakeGrid? _tryGenerateGrid(String word, int rows, int cols) {
    // Randomly shuffle letters into grid
    List<String> letters = word.split('');
    letters.shuffle(_random);

    List<List<String>> grid = [];
    int idx = 0;
    for (int r = 0; r < rows; r++) {
      List<String> row = [];
      for (int c = 0; c < cols; c++) {
        row.add(letters[idx++]);
      }
      grid.add(row);
    }

    // Now find a path that spells the original word
    List<Point>? path = _findPathForWord(grid, word, rows, cols);

    if (path != null) {
      return WordSnakeGrid(
        grid: grid,
        word: word,
        path: path,
        rows: rows,
        cols: cols,
      );
    }

    return null;
  }

  List<Point>? _findPathForWord(
      List<List<String>> grid, String word, int rows, int cols) {
    // Find all positions of first letter
    List<Point> startPositions = [];
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if (grid[y][x] == word[0]) {
          startPositions.add(Point(x, y));
        }
      }
    }

    startPositions.shuffle(_random);

    // Try each starting position
    for (var start in startPositions) {
      List<Point> path = [start];
      Set<Point> visited = {start};

      if (_findPath(grid, word, 1, start, path, visited, rows, cols)) {
        return path;
      }
    }

    return null;
  }

  bool _findPath(
    List<List<String>> grid,
    String word,
    int wordIdx,
    Point current,
    List<Point> path,
    Set<Point> visited,
    int rows,
    int cols,
  ) {
    if (wordIdx == word.length) {
      return true;
    }

    String nextLetter = word[wordIdx];

    // Shuffle directions for variety
    List<Point> dirs = List.from(_directions);
    dirs.shuffle(_random);

    for (var dir in dirs) {
      Point next = Point(current.x + dir.x, current.y + dir.y);

      if (next.x >= 0 &&
          next.x < cols &&
          next.y >= 0 &&
          next.y < rows &&
          !visited.contains(next) &&
          grid[next.y][next.x] == nextLetter) {
        path.add(next);
        visited.add(next);

        if (_findPath(grid, word, wordIdx + 1, next, path, visited, rows, cols)) {
          return true;
        }

        path.removeLast();
        visited.remove(next);
      }
    }

    return false;
  }
}