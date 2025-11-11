import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:developer' as dev;
import 'dart:math';

//============================================================================//
// CONFIGURATION
//============================================================================//

const String baseUrl = 'https://cstr-nlp-de.hf.space/gradio_api/call';
const String outputDir = './api_results';

// ANSI Color Codes for Rich Terminal Output
class Colors {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
}

//============================================================================//
// MAIN API CLIENT CLASS
//============================================================================//

class GradioApiClient {
  final http.Client _client;
  bool _isDisposed = false;
  final Set<String> _availableEndpoints = {};

  GradioApiClient() : _client = http.Client();

  void dispose() {
    _isDisposed = true;
    _client.close();
    print('${Colors.green}API Client disposed.${Colors.reset}');
  }

  //==========================================================================//
  // HEALTH CHECK - Test which endpoints are available
  //==========================================================================//

  Future<void> checkEndpointHealth() async {
    print('\n${Colors.bold}🏥 HEALTH CHECK - Testing API Endpoints${Colors.reset}');
    print('─' * 70);

    final endpoints = [
      'get_morphology',
      'check_grammar',
      'get_all_inflections',
      'get_thesaurus',
      'comprehensive_analysis',
    ];

    for (var endpoint in endpoints) {
      try {
        final testData = endpoint == 'get_morphology' 
            ? ['EN', 'en', 'test'] 
            : ['test'];
        
        final eventId = await _step1_postForEventId(endpoint, testData, silent: true);
        _availableEndpoints.add(endpoint);
        print('${Colors.green}✓${Colors.reset} $endpoint - ${Colors.green}Available${Colors.reset}');
      } catch (e) {
        print('${Colors.red}✗${Colors.reset} $endpoint - ${Colors.red}Unavailable${Colors.reset}');
        if (e.toString().contains('500')) {
          print('  ${Colors.yellow}└─ Server error: Endpoint not registered (Space may need restart)${Colors.reset}');
        }
      }
    }
    
    print('─' * 70);
    print('${Colors.cyan}Available: ${_availableEndpoints.length}/${endpoints.length} endpoints${Colors.reset}\n');
  }

  //==========================================================================//
  // GENERIC 2-STEP STREAMING API METHODS
  //==========================================================================//

  Future<String> _step1_postForEventId(
      String endpoint, List<dynamic> inputData, {bool silent = false}) async {
    if (_isDisposed) throw StateError('Client is disposed');

    final postUrl = '$baseUrl/$endpoint';
    final payload = jsonEncode({"data": inputData});

    final response = await _client.post(
      Uri.parse(postUrl),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );

    if (response.statusCode != 200) {
      if (!silent) {
        print('\n${Colors.red}━━━━ API ERROR DETAILS ━━━━${Colors.reset}');
        print('${Colors.yellow}Endpoint:${Colors.reset} $endpoint');
        print('${Colors.yellow}Status Code:${Colors.reset} ${response.statusCode}');
        print('${Colors.yellow}Response Body:${Colors.reset}');
        print(response.body);
        print('${Colors.red}━━━━━━━━━━━━━━━━━━━━━━━━${Colors.reset}\n');
      }
      throw Exception(
          'POST to $endpoint failed: ${response.statusCode}, ${response.body}');
    }

    final body = jsonDecode(response.body);
    if (body is! Map || !body.containsKey('event_id')) {
      throw Exception('No event_id in response: ${response.body}');
    }

    return body['event_id'] as String;
  }

  Future<dynamic> _step2_getStreamResults(
      String endpoint, String eventId) async {
    final getUrl = '$baseUrl/$endpoint/$eventId';
    final request = http.Request('GET', Uri.parse(getUrl));
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception('GET stream failed: ${streamedResponse.statusCode}');
    }

    final completer = Completer<dynamic>();
    String buffer = '';
    bool isComplete = false;

    streamedResponse.stream.transform(utf8.decoder).listen(
      (chunk) {
        if (isComplete) return;
        buffer += chunk;

        int messageEndIndex;
        while ((messageEndIndex = buffer.indexOf('\n\n')) != -1) {
          if (isComplete) break;
          final message = buffer.substring(0, messageEndIndex);
          buffer = buffer.substring(messageEndIndex + 2);

          final result = _parseSseMessage(message);
          if (result != null) {
            isComplete = true;
            completer.complete(result);
            break;
          }
        }
      },
      onError: (e, stackTrace) {
        if (!isComplete) {
          isComplete = true;
          completer.completeError(Exception('Stream error: $e'), stackTrace);
        }
      },
      onDone: () {
        if (!isComplete) {
          isComplete = true;
          completer.completeError(Exception('Stream ended prematurely'));
        }
      },
    );

    return completer.future;
  }

  dynamic _parseSseMessage(String messageBlock) {
    String? eventType;
    String? eventData;

    for (var line in messageBlock.split('\n')) {
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        eventData = line.substring(6).trim();
      }
    }

    if (eventType == 'complete' && eventData != null) {
      return jsonDecode(eventData);
    }

    if (eventType == 'error') {
      throw Exception('API error event: $eventData');
    }

    return null;
  }

  //==========================================================================//
  // Helper to check if endpoint is available
  //==========================================================================//

  bool _isEndpointAvailable(String endpoint) {
    if (_availableEndpoints.isEmpty) return true; // Skip check if we haven't tested
    return _availableEndpoints.contains(endpoint);
  }

  //==========================================================================//
  // 1. SPACY ANALYZER - Enhanced Visualization
  //==========================================================================//

  Future<void> testSpacyAnalyzer({
    required String testId,
    required String uiLang,
    required String modelLangKey,
    required String text,
    bool saveJson = false,
  }) async {
    _printSectionHeader('SPACY ANALYZER', testId);
    print('${Colors.cyan}Model: $modelLangKey${Colors.reset}');
    print('${Colors.cyan}Text: "$text"${Colors.reset}');
    print('─' * 70);

    if (!_isEndpointAvailable('get_morphology')) {
      print('${Colors.yellow}⚠ Endpoint not available - skipping${Colors.reset}');
      print('═' * 70 + '\n');
      return;
    }

    try {
      final eventId = await _step1_postForEventId(
          'get_morphology', [uiLang, modelLangKey, text]);
      print('${Colors.green}✓ Event ID: $eventId${Colors.reset}');

      final outputs = await _step2_getStreamResults('get_morphology', eventId);
      print('${Colors.green}✓ Stream complete${Colors.reset}\n');

      _printSpacyResults(outputs as List, testId: testId, saveJson: saveJson);
    } catch (e, st) {
      _printError('Test failed', e);
    }
    print('═' * 70 + '\n');
  }

  void _printSpacyResults(List outputs,
      {required String testId, required bool saveJson}) {
    if (outputs.length < 4) {
      print('${Colors.yellow}⚠ Expected 4 outputs, got ${outputs.length}${Colors.reset}');
      return;
    }

    // Morphological Analysis Table
    _printSubHeader('MORPHOLOGICAL & SYNTACTIC ANALYSIS');
    _printMorphologyTable(outputs[0]);

    // JSON tokens data
    final jsonTokens = outputs[1];
    if (saveJson) {
      _saveJson(jsonTokens, '$outputDir/${testId}_tokens.json');
    }

    // Named Entity Recognition
    _printSubHeader('NAMED ENTITY RECOGNITION');
    _printNER(outputs[3] as String? ?? '');

    if (jsonTokens is List && jsonTokens.isNotEmpty) {
      _printTokenStatistics(jsonTokens);
    }
  }

  void _printMorphologyTable(dynamic tableOutput) {
    if (tableOutput == null || tableOutput is! Map) {
      print('${Colors.yellow}(No table data)${Colors.reset}');
      return;
    }

    final headers = (tableOutput['headers'] as List? ?? []).cast<String>();
    final data = (tableOutput['data'] as List? ?? [])
        .map((row) => (row as List).map((cell) => cell.toString()).toList())
        .toList();

    if (headers.isEmpty || data.isEmpty) {
      print('${Colors.yellow}(No data)${Colors.reset}');
      return;
    }

    final colWidths = List<int>.filled(headers.length, 0);
    for (int i = 0; i < headers.length; i++) {
      colWidths[i] = max(headers[i].length, 8);
    }
    for (final row in data) {
      for (int i = 0; i < row.length && i < colWidths.length; i++) {
        colWidths[i] = max(colWidths[i], min(row[i].length, 40));
      }
    }

    String rowSep = '┌' + colWidths.map((w) => '─' * (w + 2)).join('┬') + '┐';
    String headerSep = '├' + colWidths.map((w) => '═' * (w + 2)).join('╪') + '┤';
    String dataSep = '├' + colWidths.map((w) => '─' * (w + 2)).join('┼') + '┤';
    String bottomSep = '└' + colWidths.map((w) => '─' * (w + 2)).join('┴') + '┘';

    print(rowSep);
    String headerRow = '│';
    for (int i = 0; i < headers.length; i++) {
      headerRow += ' ${Colors.bold}${headers[i].padRight(colWidths[i])}${Colors.reset} │';
    }
    print(headerRow);
    print(headerSep);

    for (int rowIdx = 0; rowIdx < data.length; rowIdx++) {
      final row = data[rowIdx];
      String dataRow = '│';
      for (int i = 0; i < row.length && i < colWidths.length; i++) {
        String cell = row[i].length > 40 ? row[i].substring(0, 37) + '...' : row[i];
        
        // Color code based on column
        String colored = cell;
        if (i == 0) colored = '${Colors.cyan}$cell${Colors.reset}'; // Word
        else if (i == 2) colored = '${Colors.magenta}$cell${Colors.reset}'; // POS
        else if (i == 5) colored = '${Colors.blue}$cell${Colors.reset}'; // Dependency
        
        dataRow += ' ${colored.padRight(colWidths[i] + (colored.length - cell.length))} │';
      }
      print(dataRow);
      if (rowIdx < data.length - 1) print(dataSep);
    }
    print(bottomSep);
  }

  void _printNER(String html) {
    if (html.isEmpty) {
      print('${Colors.yellow}(No NER data)${Colors.reset}');
      return;
    }

    // Check for info messages
    final pTagRegex = RegExp(r"<p.*?>(.*?)</p>", dotAll: true);
    final pMatch = pTagRegex.firstMatch(html);
    if (pMatch != null) {
      print('${Colors.yellow}${pMatch.group(1)!.trim()}${Colors.reset}');
      return;
    }

    // Parse entities
    final nerRegex = RegExp(
      r'<mark.*?>(.*?)<span.*?>(.*?)</span>.*?</mark>',
      dotAll: true,
      caseSensitive: false,
    );

    final matches = nerRegex.allMatches(html);
    if (matches.isEmpty) {
      print('${Colors.yellow}No entities found${Colors.reset}');
      return;
    }

    print('${Colors.green}✨ Found ${matches.length} entit${matches.length == 1 ? 'y' : 'ies'}:${Colors.reset}\n');
    
    for (final match in matches) {
      final text = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
      final label = match.group(2)!.trim();
      
      String labelColor = Colors.yellow;
      if (label == 'PER') labelColor = Colors.cyan;
      else if (label == 'ORG') labelColor = Colors.magenta;
      else if (label == 'LOC' || label == 'GPE') labelColor = Colors.green;
      else if (label == 'MONEY') labelColor = Colors.yellow;
      
      print('  ${Colors.bold}•${Colors.reset} ${Colors.white}$text${Colors.reset} '
            '→ $labelColor$label${Colors.reset}');
    }
  }

  void _printTokenStatistics(List tokens) {
    print('\n${Colors.bold}📊 Token Statistics:${Colors.reset}');
    
    final posCount = <String, int>{};
    int stopwords = 0;
    
    for (var token in tokens) {
      if (token is Map) {
        final pos = token['pos'] as String? ?? 'UNKNOWN';
        posCount[pos] = (posCount[pos] ?? 0) + 1;
        if (token['is_stopword'] == true) stopwords++;
      }
    }
    
    print('  Total tokens: ${Colors.cyan}${tokens.length}${Colors.reset}');
    print('  Stopwords: ${Colors.yellow}$stopwords${Colors.reset}');
    print('  POS distribution:');
    
    final sorted = posCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted.take(5)) {
      print('    ${entry.key.padRight(8)}: ${Colors.green}${'█' * (entry.value * 3)}${Colors.reset} ${entry.value}');
    }
  }

  //==========================================================================//
  // 2. GRAMMAR CHECKER - Enhanced Visualization
  //==========================================================================//

  Future<void> testGrammarCheck({
    required String testId,
    required String text,
    bool saveJson = false,
  }) async {
    _printSectionHeader('GRAMMAR CHECK', testId);
    print('${Colors.cyan}Text: "$text"${Colors.reset}');
    print('─' * 70);

    if (!_isEndpointAvailable('check_grammar')) {
      print('${Colors.yellow}⚠ Endpoint not available - skipping${Colors.reset}');
      print('${Colors.yellow}  (The Space may need to be restarted to register this endpoint)${Colors.reset}');
      print('═' * 70 + '\n');
      return;
    }

    try {
      final eventId = await _step1_postForEventId('check_grammar', [text]);
      print('${Colors.green}✓ Event ID: $eventId${Colors.reset}');

      final outputs = await _step2_getStreamResults('check_grammar', eventId);
      print('${Colors.green}✓ Stream complete${Colors.reset}\n');

      final grammarData = (outputs as List)[0];
      _printGrammarResults(grammarData, testId: testId, saveJson: saveJson);
    } catch (e, st) {
      _printError('Test failed', e);
    }
    print('═' * 70 + '\n');
  }

  void _printGrammarResults(dynamic result,
      {required String testId, required bool saveJson}) {
    _printSubHeader('GRAMMAR CHECK RESULTS');

    // Handle single map (error/info/perfect case)
    if (result is Map) {
      if (result.containsKey('error')) {
        print('${Colors.red}❌ Error: ${result['error']}${Colors.reset}');
        return;
      }
      if (result.containsKey('status') && result['status'] == 'perfect') {
        print('${Colors.green}✨ Perfect! No errors found.${Colors.reset}');
        return;
      }
      if (result.containsKey('info')) {
        print('${Colors.cyan}ℹ️  ${result['info']}${Colors.reset}');
        return;
      }
    }

    // Handle list of errors
    if (result is! List) {
      print('${Colors.yellow}⚠ Unexpected result format${Colors.reset}');
      return;
    }

    final errors = result;
    if (errors.isEmpty) {
      print('${Colors.green}✨ No errors found!${Colors.reset}');
      return;
    }

    // Check first item for special cases
    final firstItem = errors[0];
    if (firstItem is Map) {
      if (firstItem.containsKey('error')) {
        print('${Colors.red}❌ Error: ${firstItem['error']}${Colors.reset}');
        return;
      }
      if (firstItem.containsKey('status') && firstItem['status'] == 'perfect') {
        print('${Colors.green}✨ Perfect! No errors found.${Colors.reset}');
        return;
      }
      if (firstItem.containsKey('info')) {
        print('${Colors.cyan}ℹ️  ${firstItem['info']}${Colors.reset}');
        return;
      }
    }

    print('${Colors.yellow}⚠ Found ${errors.length} issue(s):${Colors.reset}\n');

    for (int i = 0; i < errors.length; i++) {
      final error = errors[i] as Map;
      
      print('┌─────────────────────────────────────────────────────────────────┐');
      print('│ ${Colors.bold}Issue ${i + 1}/${errors.length}${Colors.reset}');
      print('├─────────────────────────────────────────────────────────────────┤');
      print('│ ${Colors.red}${error['message']}${Colors.reset}');
      
      if (error['short_message'] != null && error['short_message'] != '') {
        print('│ ${Colors.yellow}Summary: ${error['short_message']}${Colors.reset}');
      }
      
      print('│');
      print('│ ${Colors.bold}Incorrect:${Colors.reset} "${Colors.red}${error['incorrect_text']}${Colors.reset}"');

      if (error['replacements'] is List &&
          (error['replacements'] as List).isNotEmpty) {
        final suggestions = (error['replacements'] as List).take(5).toList();
        print('│ ${Colors.bold}Suggestions:${Colors.reset}');
        for (var sugg in suggestions) {
          print('│   ${Colors.green}→${Colors.reset} $sugg');
        }
      }

      print('│');
      print('│ ${Colors.cyan}Rule:${Colors.reset} ${error['rule_id']}');
      print('│ ${Colors.cyan}Category:${Colors.reset} ${error['category']}');
      
      if (error['context'] != null && error['context'].toString().isNotEmpty) {
        final ctx = error['context'].toString();
        if (ctx.length > 60) {
          print('│ ${Colors.cyan}Context:${Colors.reset} ${ctx.substring(0, 57)}...');
        } else {
          print('│ ${Colors.cyan}Context:${Colors.reset} $ctx');
        }
      }

      print('└─────────────────────────────────────────────────────────────────┘');
      if (i < errors.length - 1) print('');
    }

    if (saveJson) {
      _saveJson(errors, '$outputDir/${testId}_grammar.json');
    }
  }

  //==========================================================================//
  // 3. INFLECTIONS - Enhanced Visualization
  //==========================================================================//

  Future<void> testInflections({
    required String testId,
    required String word,
    bool saveJson = false,
  }) async {
    _printSectionHeader('INFLECTIONS', testId);
    print('${Colors.cyan}Word: "$word"${Colors.reset}');
    print('─' * 70);

    if (!_isEndpointAvailable('get_all_inflections')) {
      print('${Colors.yellow}⚠ Endpoint not available - skipping${Colors.reset}');
      print('${Colors.yellow}  (The Space may need to be restarted to register this endpoint)${Colors.reset}');
      print('═' * 70 + '\n');
      return;
    }

    try {
      final eventId = await _step1_postForEventId('get_all_inflections', [word]);
      print('${Colors.green}✓ Event ID: $eventId${Colors.reset}');

      final outputs = await _step2_getStreamResults('get_all_inflections', eventId);
      print('${Colors.green}✓ Stream complete${Colors.reset}\n');

      final inflectionData = (outputs as List)[0];
      _printInflectionsResults(inflectionData as Map,
          testId: testId, saveJson: saveJson);
    } catch (e, st) {
      _printError('Test failed', e);
    }
    print('═' * 70 + '\n');
  }

  void _printInflectionsResults(Map result,
      {required String testId, required bool saveJson}) {
    _printSubHeader('INFLECTION ANALYSIS');

    if (result.containsKey('error')) {
      print('${Colors.red}❌ Error: ${result['error']}${Colors.reset}');
      return;
    }

    if (result.containsKey('info')) {
      print('${Colors.cyan}ℹ️  ${result['info']}${Colors.reset}');
      return;
    }

    print('${Colors.bold}Input Word:${Colors.reset} ${Colors.cyan}${result['input_word']}${Colors.reset}\n');

    final parserHint = result['parser_hint'] as Map?;
    if (parserHint != null) {
      print('${Colors.bold}🔍 Parser Analysis:${Colors.reset}');
      print('   POS Tag: ${Colors.magenta}${parserHint['pos'] ?? 'N/A'}${Colors.reset}');
      print('   Lemma: ${Colors.cyan}${parserHint['lemma'] ?? 'N/A'}${Colors.reset}');
      print('   Type: ${Colors.yellow}${parserHint['type'] ?? 'unknown'}${Colors.reset}\n');
    }

    final analyses = result['analyses'] as Map?;
    if (analyses == null || analyses.isEmpty) {
      print('${Colors.yellow}No inflection analyses available.${Colors.reset}');
      return;
    }

    // NOUN ANALYSIS
    if (analyses.containsKey('noun')) {
      _printNounAnalysis(analyses['noun'] as Map);
    }

    // VERB ANALYSIS
    if (analyses.containsKey('verb')) {
      _printVerbAnalysis(analyses['verb'] as Map);
    }

    // ADJECTIVE ANALYSIS
    if (analyses.containsKey('adjective')) {
      _printAdjectiveAnalysis(analyses['adjective'] as Map);
    }

    if (saveJson) {
      _saveJson(result, '$outputDir/${testId}_inflections.json');
    }
  }

  void _printNounAnalysis(Map noun) {
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}🏛️  NOUN ANALYSIS${Colors.reset}');
    print('╚═══════════════════════════════════════════════════════════════════╝\n');
    
    print('${Colors.bold}Base Form:${Colors.reset} ${Colors.cyan}${noun['base_form']}${Colors.reset}');
    print('${Colors.bold}Gender:${Colors.reset} ${Colors.magenta}${noun['gender']}${Colors.reset}');
    print('${Colors.bold}Singular:${Colors.reset} ${noun['singular']}');
    print('${Colors.bold}Plural:${Colors.reset} ${noun['plural']}\n');

    final declension = noun['declension'] as Map?;
    if (declension != null && declension.isNotEmpty) {
      print('${Colors.bold}📋 DECLENSION TABLE${Colors.reset}\n');
      
      final cases = ['Nominativ', 'Akkusativ', 'Dativ', 'Genitiv'];
      final numbers = ['Singular', 'Plural'];
      
      for (var number in numbers) {
        print('${Colors.bold}$number:${Colors.reset}');
        print('┌──────────────┬─────────────────────────┬─────────────────────────┐');
        print('│ Case         │ Definite                │ Indefinite              │');
        print('├──────────────┼─────────────────────────┼─────────────────────────┤');
        
        for (var caseName in cases) {
          final key = '$caseName $number';
          if (declension.containsKey(key)) {
            final forms = declension[key] as Map;
            final def = forms['definite'] ?? '';
            final indef = forms['indefinite'] ?? '';
            
            print('│ ${caseName.padRight(12)} │ ${Colors.green}${def.padRight(23)}${Colors.reset} │ ${Colors.yellow}${indef.padRight(23)}${Colors.reset} │');
          }
        }
        print('└──────────────┴─────────────────────────┴─────────────────────────┘\n');
      }
    }
  }

  void _printVerbAnalysis(Map verb) {
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}⚡ VERB ANALYSIS${Colors.reset}');
    print('╚═══════════════════════════════════════════════════════════════════╝\n');
    
    print('${Colors.bold}Infinitive:${Colors.reset} ${Colors.cyan}${verb['infinitive']}${Colors.reset}\n');

    final conjugation = verb['conjugation'] as Map?;
    if (conjugation != null) {
      for (var tense in conjugation.keys) {
        final forms = conjugation[tense] as Map;
        if (forms.isNotEmpty) {
          print('${Colors.bold}$tense:${Colors.reset}');
          print('┌─────────────────┬──────────────────────────────────┐');
          forms.forEach((person, form) {
            print('│ ${person.toString().padRight(15)} │ ${Colors.green}${form.toString().padRight(32)}${Colors.reset} │');
          });
          print('└─────────────────┴──────────────────────────────────┘\n');
        }
      }
    }

    final participles = verb['participles'] as Map?;
    if (participles != null && participles.isNotEmpty) {
      print('${Colors.bold}Participles:${Colors.reset}');
      participles.forEach((name, form) {
        print('  ${name.toString().padRight(25)}: ${Colors.yellow}$form${Colors.reset}');
      });
      print('');
    }

    final lexeme = verb['lexeme'];
    if (lexeme is List && lexeme.isNotEmpty) {
      print('${Colors.bold}Lexeme (${lexeme.length} forms):${Colors.reset}');
      print('  ${lexeme.take(10).join(', ')}${lexeme.length > 10 ? '...' : ''}\n');
    }
  }

  void _printAdjectiveAnalysis(Map adj) {
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}🎨 ADJECTIVE ANALYSIS${Colors.reset}');
    print('╚═══════════════════════════════════════════════════════════════════╝\n');
    
    print('${Colors.bold}Base (Predicative):${Colors.reset} ${Colors.cyan}${adj['predicative']}${Colors.reset}');
    print('${Colors.bold}Comparative:${Colors.reset} ${Colors.yellow}${adj['comparative']}${Colors.reset}');
    print('${Colors.bold}Superlative:${Colors.reset} ${Colors.green}${adj['superlative']}${Colors.reset}\n');

    final attributive = adj['attributive'] as Map?;
    if (attributive != null && attributive.isNotEmpty) {
        print('${Colors.bold}📋 ATTRIBUTIVE FORMS${Colors.reset}\n');
        
        for (var declType in attributive.keys) {
        print('${Colors.bold}$declType Declension:${Colors.reset}');
        final genders = attributive[declType] as Map;
        
        print('┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐');
        print('│              │ Nom          │ Acc          │ Dat          │ Gen          │');
        print('├──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤');
        
        for (var gender in ['Masculine', 'Feminine', 'Neuter', 'Plural']) {
            if (genders.containsKey(gender)) {
            final cases = genders[gender] as Map;
            String row = '│ ${gender.substring(0, min(12, gender.length)).padRight(12)} │';
            
            for (var caseName in ['Nom', 'Acc', 'Dat', 'Gen']) {
                if (cases.containsKey(caseName)) {
                final form = (cases[caseName] as Map)['form']?.toString() ?? '';
                final formLen = form.length;
                final truncated = form.substring(0, min(12, formLen));
                row += ' ${truncated.padRight(12)} │';
                } else {
                row += '              │';
                }
            }
            print(row);
            }
        }
        print('└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n');
        }
    }
    }

  //==========================================================================//
  // 4. THESAURUS - Enhanced Visualization
  //==========================================================================//

  Future<void> testThesaurus({
    required String testId,
    required String word,
    bool saveJson = false,
  }) async {
    _printSectionHeader('THESAURUS', testId);
    print('${Colors.cyan}Word: "$word"${Colors.reset}');
    print('─' * 70);

    if (!_isEndpointAvailable('get_thesaurus')) {
      print('${Colors.yellow}⚠ Endpoint not available - skipping${Colors.reset}');
      print('${Colors.yellow}  (The Space may need to be restarted to register this endpoint)${Colors.reset}');
      print('═' * 70 + '\n');
      return;
    }

    try {
      final eventId = await _step1_postForEventId('get_thesaurus', [word]);
      print('${Colors.green}✓ Event ID: $eventId${Colors.reset}');

      final outputs = await _step2_getStreamResults('get_thesaurus', eventId);
      print('${Colors.green}✓ Stream complete${Colors.reset}\n');

      final thesaurusData = (outputs as List)[0];
      _printThesaurusResults(thesaurusData as Map,
          testId: testId, saveJson: saveJson);
    } catch (e, st) {
      _printError('Test failed', e);
    }
    print('═' * 70 + '\n');
  }

  void _printThesaurusResults(Map result,
      {required String testId, required bool saveJson}) {
    _printSubHeader('THESAURUS RESULTS');

    if (result.containsKey('error')) {
      print('${Colors.red}❌ Error: ${result['error']}${Colors.reset}');
      return;
    }

    if (result.containsKey('info')) {
      print('${Colors.cyan}ℹ️  ${result['info']}${Colors.reset}');
      return;
    }

    print('${Colors.bold}Input Word:${Colors.reset} ${Colors.cyan}${result['input_word']}${Colors.reset}\n');

    final senses = result['senses'] as List?;
    if (senses == null || senses.isEmpty) {
      print('${Colors.yellow}No senses found.${Colors.reset}');
      return;
    }

    print('${Colors.green}Found ${senses.length} sense(s)${Colors.reset}\n');

    for (int i = 0; i < senses.length; i++) {
      final sense = senses[i] as Map;
      
      print('┌─────────────────────────────────────────────────────────────────┐');
      print('│ ${Colors.bold}Sense ${i + 1}/${senses.length}: ${sense['pos'].toString().toUpperCase()}${Colors.reset}');
      print('├─────────────────────────────────────────────────────────────────┤');
      
      final definition = sense['definition'].toString();
      if (definition.length > 60) {
        final words = definition.split(' ');
        String line = '│ ${Colors.bold}Definition:${Colors.reset} ';
        for (var word in words) {
          if (line.length + word.length > 64) {
            print(line);
            line = '│              ';
          }
          line += '$word ';
        }
        if (line.trim().length > 1) print(line);
      } else {
        print('│ ${Colors.bold}Definition:${Colors.reset} $definition');
      }
      print('│');

      _printRelationList('│ ${Colors.green}🔄 Synonyms:${Colors.reset}', sense['synonyms']);
      _printRelationList('│ ${Colors.red}⚡ Antonyms:${Colors.reset}', sense['antonyms']);
      _printRelationList('│ ${Colors.cyan}⬆️  Hypernyms:${Colors.reset}', sense['hypernyms (is a type of)']);
      _printRelationList('│ ${Colors.magenta}⬇️  Hyponyms:${Colors.reset}', sense['hyponyms (examples are)']);
      _printRelationList('│ ${Colors.yellow}🔗 Holonyms:${Colors.reset}', sense['holonyms (is part of)']);
      _printRelationList('│ ${Colors.blue}🧩 Meronyms:${Colors.reset}', sense['meronyms (has parts)']);
      
      print('└─────────────────────────────────────────────────────────────────┘');
      if (i < senses.length - 1) print('');
    }

    if (saveJson) {
      _saveJson(result, '$outputDir/${testId}_thesaurus.json');
    }
  }

  void _printRelationList(String label, dynamic items) {
    if (items is List && items.isNotEmpty) {
      final itemsStr = items.take(8).join(', ');
      final more = items.length > 8 ? ' (+${items.length - 8} more)' : '';
      
      if (itemsStr.length + label.length > 60) {
        print(label);
        final words = itemsStr.split(', ');
        String line = '│     ';
        for (var word in words) {
          if (line.length + word.length > 64) {
            print(line);
            line = '│     ';
          }
          line += '$word, ';
        }
        if (line.trim().length > 1) {
          line = line.substring(0, line.length - 2); // Remove trailing comma
          print('$line$more');
        }
      } else {
        print('$label $itemsStr$more');
      }
    }
  }

  //==========================================================================//
  // 5. COMPREHENSIVE ANALYSIS - Enhanced Visualization
  //==========================================================================//

  Future<void> testComprehensiveAnalysis({
    required String testId,
    required String text,
    bool saveJson = false,
  }) async {
    _printSectionHeader('COMPREHENSIVE ANALYSIS', testId);
    print('${Colors.cyan}Text: "$text"${Colors.reset}');
    print('─' * 70);

    if (!_isEndpointAvailable('comprehensive_analysis')) {
      print('${Colors.yellow}⚠ Endpoint not available - skipping${Colors.reset}');
      print('${Colors.yellow}  (The Space may need to be restarted to register this endpoint)${Colors.reset}');
      print('═' * 70 + '\n');
      return;
    }

    try {
      final eventId = await _step1_postForEventId('comprehensive_analysis', [text]);
      print('${Colors.green}✓ Event ID: $eventId${Colors.reset}');

      final outputs = await _step2_getStreamResults('comprehensive_analysis', eventId);
      print('${Colors.green}✓ Stream complete${Colors.reset}\n');

      final comprehensiveData = (outputs as List)[0];
      _printComprehensiveResults(comprehensiveData as Map,
          testId: testId, saveJson: saveJson);
    } catch (e, st) {
      _printError('Test failed', e);
    }
    print('═' * 70 + '\n');
  }

  void _printComprehensiveResults(Map result,
      {required String testId, required bool saveJson}) {
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}🎯 COMPREHENSIVE ANALYSIS RESULTS${Colors.reset}');
    print('╚═══════════════════════════════════════════════════════════════════╝\n');

    if (result.containsKey('error')) {
      print('${Colors.red}❌ Error: ${result['error']}${Colors.reset}');
      return;
    }

    print('${Colors.bold}Input Text:${Colors.reset} "${Colors.cyan}${result['input_text']}${Colors.reset}"\n');

    // 1. Grammar Check
    if (result.containsKey('grammar_check')) {
      print('╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}1️⃣  GRAMMAR CHECK${Colors.reset}');
      print('╚═══════════════════════════════════════════════════════════════════╝\n');
      _printGrammarResults(
        result['grammar_check'],
        testId: '${testId}_grammar',
        saveJson: false,
      );
      print('');
    }

    // 2. spaCy Analysis Summary
    if (result.containsKey('spacy_analysis')) {
      print('╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}2️⃣  SPACY MORPHO-SYNTACTIC ANALYSIS${Colors.reset}');
      print('╚═══════════════════════════════════════════════════════════════════╝\n');
      
      final spacyData = result['spacy_analysis'];
      if (spacyData is List && spacyData.isNotEmpty) {
        print('${Colors.green}Analyzed ${spacyData.length} token(s)${Colors.reset}\n');
        
        // Compact table view
        print('┌────────────┬────────────┬──────┬──────────────────────┬────────────┐');
        print('│ Word       │ Lemma      │ POS  │ Morphology           │ Dependency │');
        print('├────────────┼────────────┼──────┼──────────────────────┼────────────┤');
        
        for (var token in spacyData) {
          final t = token as Map;
          final word = _truncate(t['word'] as String, 10);
          final lemma = _truncate(t['lemma'] as String, 10);
          final pos = _truncate(t['pos'] as String, 5);
          final morph = _truncate(t['morphology'] as String, 20);
          final dep = _truncate(t['dependency'] as String, 10);
          
          print('│ ${Colors.cyan}${word.padRight(10)}${Colors.reset} │ ${lemma.padRight(10)} │ ${Colors.magenta}${pos.padRight(5)}${Colors.reset} │ ${morph.padRight(20)} │ ${Colors.blue}${dep.padRight(10)}${Colors.reset} │');
        }
        print('└────────────┴────────────┴──────┴──────────────────────┴────────────┘\n');
        
      } else if (spacyData is Map && spacyData.containsKey('error')) {
        print('${Colors.red}❌ ${spacyData['error']}${Colors.reset}\n');
      }
    }

    // 3. Token Deep Dive
    if (result.containsKey('token_deep_dive')) {
      print('╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}3️⃣  TOKEN-BY-TOKEN DEEP DIVE${Colors.reset}');
      print('╚═══════════════════════════════════════════════════════════════════╝\n');
      
      final tokens = result['token_deep_dive'] as List;
      
      for (int i = 0; i < tokens.length; i++) {
        final token = tokens[i] as Map;
        
        print('┌─────────────────────────────────────────────────────────────────┐');
        print('│ ${Colors.bold}Token ${(i + 1).toString().padLeft(2)}/${tokens.length}: "${Colors.cyan}${token['word']}${Colors.reset}"${Colors.reset}');
        print('├─────────────────────────────────────────────────────────────────┤');
        print('│ 🔬 ${Colors.bold}spaCy:${Colors.reset} POS=${Colors.magenta}${token['spacy_pos']}${Colors.reset}, Lemma=${Colors.cyan}${token['spacy_lemma']}${Colors.reset}');
        
        // Pattern.de Analysis
        final patternAnalyses = token['pattern_analyses'] as Map?;
        if (patternAnalyses != null && patternAnalyses.isNotEmpty) {
          if (patternAnalyses.containsKey('error')) {
            print('│ 📚 ${Colors.bold}Pattern:${Colors.reset} ${Colors.red}${patternAnalyses['error']}${Colors.reset}');
          } else if (patternAnalyses.containsKey('info')) {
            print('│ 📚 ${Colors.bold}Pattern:${Colors.reset} ${Colors.yellow}${patternAnalyses['info']}${Colors.reset}');
          } else {
            final types = patternAnalyses.keys.join(', ');
            print('│ 📚 ${Colors.bold}Pattern:${Colors.reset} ${Colors.green}[$types]${Colors.reset}');
            
            // Show brief summary
            if (patternAnalyses.containsKey('noun')) {
              final noun = patternAnalyses['noun'] as Map;
              print('│    └─ ${Colors.cyan}Noun:${Colors.reset} ${noun['gender']}, Base: ${noun['base_form']}');
            }
            if (patternAnalyses.containsKey('verb')) {
              final verb = patternAnalyses['verb'] as Map;
              print('│    └─ ${Colors.green}Verb:${Colors.reset} Infinitive: ${verb['infinitive']}');
            }
            if (patternAnalyses.containsKey('adjective')) {
              final adj = patternAnalyses['adjective'] as Map;
              print('│    └─ ${Colors.yellow}Adj:${Colors.reset} ${adj['predicative']} → ${adj['comparative']} → ${adj['superlative']}');
            }
          }
        }
        
        // Thesaurus
        final thesaurusSenses = token['thesaurus_senses'];
        if (thesaurusSenses is List && thesaurusSenses.isNotEmpty) {
          print('│ 📖 ${Colors.bold}Thesaurus:${Colors.reset} ${Colors.green}${thesaurusSenses.length} sense(s)${Colors.reset}');
          
          for (var sense in thesaurusSenses.take(2)) {
            final s = sense as Map;
            final synonyms = (s['synonyms'] as List? ?? []).take(5).join(', ');
            if (synonyms.isNotEmpty) {
              print('│    └─ ${Colors.magenta}${s['pos']}:${Colors.reset} $synonyms');
            }
          }
        } else if (token.containsKey('thesaurus_info')) {
          print('│ 📖 ${Colors.bold}Thesaurus:${Colors.reset} ${Colors.yellow}${token['thesaurus_info']}${Colors.reset}');
        }
        
        print('└─────────────────────────────────────────────────────────────────┘');
        if (i < tokens.length - 1) print('');
      }
    }

    if (saveJson) {
      _saveJson(result, '$outputDir/${testId}_comprehensive.json');
    }
  }

  //==========================================================================//
  // HELPER METHODS
  //==========================================================================//

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return text.substring(0, maxLen - 3) + '...';
  }

  void _printSectionHeader(String title, String testId) {
    print('\n╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}$title${Colors.reset} ${Colors.cyan}($testId)${Colors.reset}');
    print('╚═══════════════════════════════════════════════════════════════════╝');
  }

  void _printSubHeader(String title) {
    print('${Colors.bold}$title${Colors.reset}');
    print('─' * 70);
  }

  void _printError(String message, dynamic error) {
    print('${Colors.red}❌ $message: $error${Colors.reset}');
  }

  void _saveJson(dynamic data, String path) {
    try {
      final jsonStr = JsonEncoder.withIndent('  ').convert(data);
      File(path).writeAsStringSync(jsonStr);
      print('${Colors.green}💾 JSON saved to $path${Colors.reset}');
    } catch (e) {
      print('${Colors.red}❌ Error saving JSON: $e${Colors.reset}');
    }
  }
}

//============================================================================//
// MAIN FUNCTION - COMPREHENSIVE TEST SUITE
//============================================================================//

Future<void> main(List<String> args) async {
  print('\n╔═══════════════════════════════════════════════════════════════════╗');
  print('║ ${Colors.bold}🏛️  CONSOLIDATED LINGUISTICS HUB - COMPREHENSIVE SHOWCASE${Colors.reset}    ║');
  print('╚═══════════════════════════════════════════════════════════════════╝\n');

  final saveJson = args.contains('--save-json');
  final skipHealth = args.contains('--skip-health');
  final testFilter = args.where((arg) => !arg.startsWith('--')).toList();

  if (saveJson) {
    try {
      Directory(outputDir).createSync(recursive: true);
      print('${Colors.green}📂 Output directory: $outputDir${Colors.reset}');
      print('${Colors.green}   └─ Saving JSON results${Colors.reset}\n');
    } catch (e) {
      print('${Colors.red}❌ FATAL: Cannot create output directory: $e${Colors.reset}\n');
      return;
    }
  }

  final api = GradioApiClient();

  try {
    // Health check first
    if (!skipHealth) {
      await api.checkEndpointHealth();
    }

    final runAll = testFilter.isEmpty || testFilter.contains('all');
    final runSpacy = runAll || testFilter.contains('spacy');
    final runGrammar = runAll || testFilter.contains('grammar');
    final runInflections = runAll || testFilter.contains('inflections');
    final runThesaurus = runAll || testFilter.contains('thesaurus');
    final runComprehensive = runAll || testFilter.contains('comprehensive');

    //========================================================================//
    // 1. SPACY ANALYZER TESTS
    //========================================================================//
    if (runSpacy) {
      print('\n╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}TEST SUITE 1: SPACY ANALYZER (Multi-lingual)${Colors.reset}                  ║');
      print('╚═══════════════════════════════════════════════════════════════════╝');

      await api.testSpacyAnalyzer(
        testId: 'spacy_en_complex',
        uiLang: 'EN',
        modelLangKey: 'en',
        text: 'The quick brown fox jumps over the lazy dog near the riverbank.',
        saveJson: saveJson,
      );

      await api.testSpacyAnalyzer(
        testId: 'spacy_de_complex',
        uiLang: 'DE',
        modelLangKey: 'de',
        text: 'Der fleißige Student lernt jeden Tag Deutsch in der Bibliothek.',
        saveJson: saveJson,
      );

      await api.testSpacyAnalyzer(
        testId: 'spacy_es',
        uiLang: 'ES',
        modelLangKey: 'es',
        text: 'María estudia medicina en la Universidad de Barcelona.',
        saveJson: saveJson,
      );
    }

    //========================================================================//
    // 2. GRAMMAR CHECKER TESTS
    //========================================================================//
    if (runGrammar) {
      print('\n╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}TEST SUITE 2: GRAMMAR CHECKER (German)${Colors.reset}                        ║');
      print('╚═══════════════════════════════════════════════════════════════════╝');

      await api.testGrammarCheck(
        testId: 'grammar_spelling_error',
        text: 'Das ist ein Huas mit großem Garten.',
        saveJson: saveJson,
      );

      await api.testGrammarCheck(
        testId: 'grammar_agreement_error',
        text: 'Die Katze schlafen auf dem Tisch.',
        saveJson: saveJson,
      );

      await api.testGrammarCheck(
        testId: 'grammar_perfect',
        text: 'Die Sonne scheint hell am klaren Himmel.',
        saveJson: saveJson,
      );
    }

    //========================================================================//
    // 3. INFLECTIONS TESTS
    //========================================================================//
    if (runInflections) {
      print('\n╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}TEST SUITE 3: INFLECTIONS (German)${Colors.reset}                            ║');
      print('╚═══════════════════════════════════════════════════════════════════╝');

      await api.testInflections(
        testId: 'inflect_noun_haus',
        word: 'Haus',
        saveJson: saveJson,
      );

      await api.testInflections(
        testId: 'inflect_verb_gehen',
        word: 'gehen',
        saveJson: saveJson,
      );

      await api.testInflections(
        testId: 'inflect_adj_schön',
        word: 'schön',
        saveJson: saveJson,
      );
    }

    //========================================================================//
    // 4. THESAURUS TESTS
    //========================================================================//
    if (runThesaurus) {
      print('\n╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}TEST SUITE 4: THESAURUS (German WordNet)${Colors.reset}                      ║');
      print('╚═══════════════════════════════════════════════════════════════════╝');

      await api.testThesaurus(
        testId: 'thesaurus_hund',
        word: 'Hund',
        saveJson: saveJson,
      );

      await api.testThesaurus(
        testId: 'thesaurus_gut',
        word: 'gut',
        saveJson: saveJson,
      );

      await api.testThesaurus(
        testId: 'thesaurus_laufen',
        word: 'laufen',
        saveJson: saveJson,
      );
    }

    //========================================================================//
    // 5. COMPREHENSIVE ANALYSIS TESTS (THE SHOWCASE!)
    //========================================================================//
    if (runComprehensive) {
      print('\n╔═══════════════════════════════════════════════════════════════════╗');
      print('║ ${Colors.bold}TEST SUITE 5: COMPREHENSIVE ANALYSIS (All Tools)${Colors.reset}              ║');
      print('╚═══════════════════════════════════════════════════════════════════╝');

      await api.testComprehensiveAnalysis(
        testId: 'comprehensive_simple',
        text: 'Die Katze schläft.',
        saveJson: saveJson,
      );

      await api.testComprehensiveAnalysis(
        testId: 'comprehensive_complex',
        text: 'Der schnelle braune Fuchs springt über den faulen Hund.',
        saveJson: saveJson,
      );

      await api.testComprehensiveAnalysis(
        testId: 'comprehensive_with_error',
        text: 'Die Katze schlafen auf dem Tisch.',
        saveJson: saveJson,
      );
    }

    print('\n╔═══════════════════════════════════════════════════════════════════╗');
    print('║ ${Colors.bold}${Colors.green}✅ ALL TESTS COMPLETED${Colors.reset}${Colors.reset}                                        ║');
    print('╚═══════════════════════════════════════════════════════════════════╝');
    
    if (saveJson) {
      print('\n${Colors.cyan}📁 All results saved to: $outputDir${Colors.reset}');
    }
    
    print('\n${Colors.yellow}💡 Usage:${Colors.reset}');
    print('   dart test_nlp_showcase.dart                  # Run all tests with health check');
    print('   dart test_nlp_showcase.dart --save-json      # Save JSON outputs');
    print('   dart test_nlp_showcase.dart --skip-health    # Skip health check');
    print('   dart test_nlp_showcase.dart spacy            # Run only spaCy tests');
    print('   dart test_nlp_showcase.dart comprehensive    # Run only comprehensive tests');
    
    print('\n${Colors.cyan}🔧 Troubleshooting:${Colors.reset}');
    print('   If endpoints are unavailable, the Gradio Space may need to be restarted.');
    print('   Visit: https://huggingface.co/spaces/CrispStrobe/spacy-de\n');

  } catch (e, st) {
    print('${Colors.red}❌ Critical error in test suite: $e${Colors.reset}');
    print(st);
  } finally {
    api.dispose();
  }
}