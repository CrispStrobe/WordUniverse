import 'dart:io';
import 'dart:math';

class Colors {
  static const String reset = '\x1B[0m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
  static const String bold = '\x1B[1m';
}

class Point {
  int x, y;
  Point(this.x, this.y);
  
  @override
  bool operator ==(Object other) => other is Point && other.x == x && other.y == y;
  
  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

enum Difficulty { easy, medium, hard, expert }

class WordSnakeGrid {
  final List<List<String>> grid;
  final String word;
  final List<Point> path;
  
  WordSnakeGrid(this.grid, this.word, this.path);
}

class WordSnakeGenerator {
  final Random random = Random();
  
  final List<Point> directions = [
    Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1),
  ];
  
  WordSnakeGrid? generate(String word, Difficulty difficulty) {
    word = word.toUpperCase();
    
    List<List<int>> dimensions = _getPossibleDimensions(word.length, difficulty);
    dimensions.shuffle(random);
    
    for (var dim in dimensions) {
      int rows = dim[0];
      int cols = dim[1];
      
      // Try many random arrangements
      for (int attempt = 0; attempt < 500; attempt++) {
        var grid = _tryGenerateGrid(word, rows, cols);
        if (grid != null) return grid;
      }
    }
    
    return null;
  }
  
  List<List<int>> _getPossibleDimensions(int length, Difficulty difficulty) {
    List<List<int>> dims = [];
    
    for (int rows = 2; rows <= length; rows++) {
      if (length % rows == 0) {
        int cols = length ~/ rows;
        
        bool valid = false;
        switch (difficulty) {
          case Difficulty.easy:
            valid = (rows == 2 && cols <= 3) || (cols == 2 && rows <= 3);
            break;
          case Difficulty.medium:
            valid = (rows <= 3 && cols <= 4) || (cols <= 3 && rows <= 4);
            break;
          case Difficulty.hard:
            valid = (rows <= 4 && cols <= 4);
            break;
          case Difficulty.expert:
            valid = rows <= 5 && cols <= 5;
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
    // RANDOMLY shuffle letters into grid
    List<String> letters = word.split('');
    letters.shuffle(random);
    
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
      return WordSnakeGrid(grid, word, path);
    }
    
    return null;
  }
  
  List<Point>? _findPathForWord(List<List<String>> grid, String word, int rows, int cols) {
    // Find all positions of first letter
    List<Point> startPositions = [];
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if (grid[y][x] == word[0]) {
          startPositions.add(Point(x, y));
        }
      }
    }
    
    startPositions.shuffle(random);
    
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
  
  bool _findPath(List<List<String>> grid, String word, int wordIdx, 
                 Point current, List<Point> path, Set<Point> visited, int rows, int cols) {
    if (wordIdx == word.length) {
      return true;
    }
    
    String nextLetter = word[wordIdx];
    
    // Shuffle directions for variety
    List<Point> dirs = List.from(directions);
    dirs.shuffle(random);
    
    for (var dir in dirs) {
      Point next = Point(current.x + dir.x, current.y + dir.y);
      
      if (next.x >= 0 && next.x < cols && next.y >= 0 && next.y < rows && 
          !visited.contains(next) && grid[next.y][next.x] == nextLetter) {
        
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
  
  void display(WordSnakeGrid grid, {bool showSolution = false}) {
    for (int y = 0; y < grid.grid.length; y++) {
      for (int x = 0; x < grid.grid[y].length; x++) {
        String cell = grid.grid[y][x];
        
        if (showSolution) {
          int idx = grid.path.indexWhere((p) => p.x == x && p.y == y);
          if (idx >= 0) {
            String num = (idx + 1).toString().padLeft(2, '0');
            stdout.write('${Colors.green}${Colors.bold}$cell$num${Colors.reset} ');
          } else {
            stdout.write('${Colors.yellow}$cell  ${Colors.reset} ');
          }
        } else {
          stdout.write('${Colors.yellow}${Colors.bold}$cell${Colors.reset}   ');
        }
      }
      print('');
    }
    
    if (showSolution) {
      print('\n${Colors.green}${Colors.bold}Lösung: ${grid.word}${Colors.reset}');
    } else {
      print('${Colors.white}Verbinde die Buchstaben!${Colors.reset}');
    }
  }
}

class WordSnakeApp {
  final WordSnakeGenerator generator = WordSnakeGenerator();
  
  void run(List<String> args) {
    print('${Colors.bold}${Colors.magenta}');
    print('╔══════════════════════════════════════════════════════╗');
    print('║         🐍 WORTSCHLANGEN GENERATOR 🐍               ║');
    print('╚══════════════════════════════════════════════════════╝');
    print(Colors.reset);
    print('');
    
    String filename = 'hamburg.txt';
    Difficulty difficulty = Difficulty.medium;
    int count = 5;
    bool showSolutions = false;
    
    for (int i = 0; i < args.length; i++) {
      if (args[i] == '--file' && i + 1 < args.length) {
        filename = args[i + 1];
      } else if (args[i] == '--difficulty' && i + 1 < args.length) {
        difficulty = _parseDifficulty(args[i + 1]);
      } else if (args[i] == '--count' && i + 1 < args.length) {
        count = int.tryParse(args[i + 1]) ?? 5;
      } else if (args[i] == '--solutions') {
        showSolutions = true;
      } else if (args[i] == '--help') {
        _showHelp();
        return;
      }
    }
    
    List<String> words = _loadWords(filename);
    if (words.isEmpty) {
      print('${Colors.red}Keine Wörter gefunden in $filename${Colors.reset}');
      return;
    }
    
    print('${Colors.green}✓ ${words.length} Wörter geladen${Colors.reset}');
    print('${Colors.cyan}Schwierigkeit: ${difficulty.name}${Colors.reset}\n');
    
    List<String> filtered = _filterWords(words, difficulty);
    filtered.shuffle();
    
    int generated = 0;
    int tried = 0;
    
    for (var word in filtered) {
      if (generated >= count) break;
      tried++;
      if (tried > count * 10) break; // Give up after too many attempts
      
      var grid = generator.generate(word, difficulty);
      if (grid != null) {
        generated++;
        print('${Colors.cyan}${Colors.bold}═══ Rätsel #$generated ═══${Colors.reset}');
        print('${Colors.white}${word.length} Buchstaben${Colors.reset}\n');
        generator.display(grid, showSolution: showSolutions);
        print('');
      }
    }
    
    if (generated < count) {
      print('${Colors.yellow}Hinweis: $generated von $count Rätseln generiert${Colors.reset}');
    }
    
    print('${Colors.green}${Colors.bold}Fertig! Viel Spaß! 🎉${Colors.reset}');
  }
  
  Difficulty _parseDifficulty(String s) {
    switch (s.toLowerCase()) {
      case 'easy': case 'leicht': return Difficulty.easy;
      case 'hard': case 'schwer': return Difficulty.hard;
      case 'expert': case 'experte': return Difficulty.expert;
      default: return Difficulty.medium;
    }
  }
  
  List<String> _loadWords(String filename) {
    try {
      return File(filename).readAsLinesSync()
          .map((l) => l.split(',')[0].trim())
          .where((w) => w.isNotEmpty && !w.startsWith('#'))
          .toList();
    } catch (e) {
      return [];
    }
  }
  
  List<String> _filterWords(List<String> words, Difficulty d) {
    return words.where((w) {
      int len = w.length;
      if (len < 4 || len > 12) return false;
      
      for (int r = 2; r <= len; r++) {
        if (len % r == 0) {
          int c = len ~/ r;
          if (r <= 5 && c <= 5) return true;
        }
      }
      return false;
    }).toList();
  }
  
  void _showHelp() {
    print('''
${Colors.bold}Verwendung:${Colors.reset}
  dart snake.dart [OPTIONEN]

${Colors.bold}Optionen:${Colors.reset}
  --file DATEI        Wortliste (Standard: hamburg.txt)
  --difficulty LEVEL  easy, medium, hard, expert (Standard: medium)
  --count N           Anzahl Rätsel (Standard: 5)
  --solutions         Lösungen anzeigen
  --help              Diese Hilfe

${Colors.bold}Beispiele:${Colors.reset}
  dart snake.dart --difficulty hard --count 10
  dart snake.dart --solutions
''');
  }
}

void main(List<String> args) {
  WordSnakeApp().run(args);
}