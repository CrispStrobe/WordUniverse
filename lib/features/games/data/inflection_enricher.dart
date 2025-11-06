import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

//============================================================================//
// CONFIGURATION
//============================================================================//

const String baseUrl = 'https://cstr-nlp-de.hf.space/gradio_api/call';
// --- FIXED PATHS ---
// Make paths relative to the script location for robustness
final String scriptDir = path.dirname(Platform.script.toFilePath());
final String inputFilePath = path.normalize(path.join(scriptDir, 'grundwortschatz_with_errors.json'));
final String backupDir = path.normalize(path.join(scriptDir, 'backups'));

const int batchSize = 10; // Save after processing this many words
const Duration apiDelay = Duration(milliseconds: 500); // Delay between API calls

// ANSI Colors
class Colors {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String cyan = '\x1B[36m';
}

//============================================================================//
// API CLIENT (Unchanged)
//============================================================================//

class NLPApiClient {
  final http.Client _client = http.Client();
  
  Future<Map<String, dynamic>?> getInflections(String word, String wordType) async {
    try {
      // Step 1: POST to get event_id
      final postUrl = '$baseUrl/get_all_inflections';
      
      // NEW: Get the POS hint
      final String posHint = _mapWordTypeToPosHint(wordType);
      
      // MODIFIED: Payload now includes the POS hint
      final payload = jsonEncode({
        "data": [word, posHint] // Pass [word, hint]
      });
      
      final response = await _client.post(
        Uri.parse(postUrl),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      
      if (response.statusCode != 200) {
        print('${Colors.red}  ✗ API POST failed: ${response.statusCode}${Colors.reset}');
        return null;
      }
      
      final body = jsonDecode(response.body);
      if (body is! Map || !body.containsKey('event_id')) {
        print('${Colors.red}  ✗ No event_id in response${Colors.reset}');
        return null;
      }
      
      final eventId = body['event_id'] as String;
      
      // Step 2: GET streaming results
      final getUrl = '$baseUrl/get_all_inflections/$eventId';
      final request = http.Request('GET', Uri.parse(getUrl));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      
      final streamedResponse = await _client.send(request);
      
      if (streamedResponse.statusCode != 200) {
        print('${Colors.red}  ✗ API stream failed: ${streamedResponse.statusCode}${Colors.reset}');
        return null;
      }
      
      final completer = Completer<Map<String, dynamic>?>();
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
        onError: (e) {
          if (!isComplete) {
            isComplete = true;
            completer.completeError(e);
          }
        },
        onDone: () {
          if (!isComplete) {
            isComplete = true;
            completer.complete(null);
          }
        },
      );
      
      return await completer.future;
    } catch (e) {
      print('${Colors.red}  ✗ API error: $e${Colors.reset}');
      return null;
    }
  }

  // Helper to map our enum string to the API's POS hint
  String _mapWordTypeToPosHint(String wordType) {
    switch (wordType) {
      case 'verb':
        return 'VB'; // Verb
      case 'substantiv':
        return 'NN'; // Noun
      case 'adjektiv':
        return 'ADJ'; // Adjective
      case 'pronomen':
        return 'PRON'; // Pronoun
      // The API might not support others, but '' is a safe default.
      default:
        return ''; // Let the API guess if we don't have a hint
    }
  }
  
  Map<String, dynamic>? _parseSseMessage(String messageBlock) {
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
      try {
         final parsed = jsonDecode(eventData);
        if (parsed is List && parsed.isNotEmpty) {
          return parsed[0] as Map<String, dynamic>;
        }
      } catch (e) {
        print('${Colors.red}  ✗ Error parsing API JSON: $e${Colors.reset}');
        return null;
      }
    }
    
    return null;
  }
  
  void dispose() {
    _client.close();
  }
}

//============================================================================//
// FILE MANAGER (Unchanged)
//============================================================================//

class VocabularyFileManager {
  final String filePath;
  final String tempFilePath;
  final String backupDirPath;
  
  Map<String, dynamic> data = {};
  
  VocabularyFileManager(this.filePath)
      : tempFilePath = '$filePath.tmp',
        backupDirPath = backupDir;
  
  Future<void> load() async {
    print('${Colors.cyan}📂 Loading vocabulary file...${Colors.reset}');
    
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Input file not found: $filePath\nRun `dart run convert_to_json.py` first.');
    }
    
    final contents = await file.readAsString();
    data = jsonDecode(contents) as Map<String, dynamic>;
    
    final vocabList = data['vocabulary'] as List?;
    if (vocabList == null) {
      throw Exception('No "vocabulary" array found in JSON');
    }
    
    print('${Colors.green}✓ Loaded ${vocabList.length} words${Colors.reset}');
  }
  
  Future<void> createBackup() async {
    print('${Colors.cyan}💾 Creating backup...${Colors.reset}');
    
    final backupFolder = Directory(backupDirPath);
    if (!backupFolder.existsSync()) {
      backupFolder.createSync(recursive: true);
    }
    
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = path.join(backupDirPath, 'grundwortschatz_backup_$timestamp.json');
    
    await File(filePath).copy(backupPath);
    print('${Colors.green}✓ Backup saved to: $backupPath${Colors.reset}');
  }
  
  Future<void> saveAtomic() async {
    // Write to temporary file first
    final tempFile = File(tempFilePath);
    // Use the same indent as the python script
    final encoder = JsonEncoder.withIndent('  '); 
    final jsonString = encoder.convert(data);
    
    await tempFile.writeAsString(jsonString);
    
    // Atomic rename
    await tempFile.rename(filePath);
  }
  
  List<Map<String, dynamic>> getVocabulary() {
    return (data['vocabulary'] as List).cast<Map<String, dynamic>>();
  }
  
  void updateMetadata(String key, dynamic value) {
    final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
    metadata[key] = value;
    data['metadata'] = metadata;
  }
}

//============================================================================//
// *** FIXED *** ENRICHMENT ENGINE
//============================================================================//

class VocabularyEnricher {
  final VocabularyFileManager fileManager;
  final NLPApiClient apiClient;
  
  int totalWords = 0;
  int alreadyEnriched = 0;
  int successfullyEnriched = 0;
  int failedEnrichment = 0;
  int skipped = 0;
  
  VocabularyEnricher(this.fileManager, this.apiClient);
  
  Future<void> enrich() async {
    final vocabulary = fileManager.getVocabulary();
    totalWords = vocabulary.length;
    
    print('\n${Colors.bold}🔬 Starting enrichment process...${Colors.reset}');
    print('${Colors.cyan}Total words: $totalWords${Colors.reset}\n');
    
    int processedInBatch = 0;
    
    for (int i = 0; i < vocabulary.length; i++) {
      final wordEntry = vocabulary[i];
      final word = wordEntry['word'] as String;
      final wordType = wordEntry['wordType'] as String;
      final id = wordEntry['id'] as String;
      
      print('${Colors.cyan}[${i + 1}/$totalWords]${Colors.reset} Processing: ${Colors.bold}$word${Colors.reset} ($wordType, $id)');
      
      // --- *** FIX 1: "Already Enriched" Check *** ---
      // Check if data is *valid*, not just *present*.
      // This allows us to retry failed words ('status': 'no_data_available')
      final existingData = wordEntry['inflectionData'];
      if (existingData != null &&
          existingData is Map<String, dynamic> &&
          _isValidInflectionData(existingData)) {
        print('  ${Colors.yellow}⊘ Already enriched - skipping${Colors.reset}');
        alreadyEnriched++;
        continue;
      }
      
      // Skip if not a word type that has inflections
      if (!_shouldEnrich(wordType)) {
        print('  ${Colors.blue}⊘ Word type "$wordType" doesn\'t need inflections - skipping${Colors.reset}');
        skipped++;
        continue;
      }
      
      // Call API
      final inflectionData = await apiClient.getInflections(word, wordType);
      
      if (inflectionData != null) {
        
        // --- *** FIX 2: Validation Logic *** ---
        // Check API data against the (correct) `genus` from Python
        bool isDataValid = _validateApiData(wordEntry, inflectionData);

        if (isDataValid && _isValidInflectionData(inflectionData)) {
          wordEntry['inflectionData'] = inflectionData;
          wordEntry['inflectionDataEnrichedAt'] = DateTime.now().toIso8601String();
          successfullyEnriched++;
          print('  ${Colors.green}✓ Enriched successfully${Colors.reset}');
          
          // --- *** FIX 3: Populate Top-Level Fields *** ---
          // Use the new data to fill in the `plural` field
          _populateTopLevelFields(wordEntry, inflectionData);

        } else if (!isDataValid) {
          // We actively rejected it due to data conflict
          print('  ${Colors.red}✗ CONFLICT: API data rejected (e.g., wrong gender).${Colors.reset}');
          wordEntry['inflectionData'] = {'status': 'conflict_rejected'};
          wordEntry['inflectionDataEnrichedAt'] = DateTime.now().toIso8601String();
          failedEnrichment++;
        } else {
          // API returned no useful data
          print('  ${Colors.yellow}⚠ API returned no useful data${Colors.reset}');
          wordEntry['inflectionData'] = {'status': 'no_data_available'};
          wordEntry['inflectionDataEnrichedAt'] = DateTime.now().toIso8601String();
          failedEnrichment++;
        }
      } else {
        print('  ${Colors.red}✗ API call failed${Colors.reset}');
        failedEnrichment++;
        // Do not set 'inflectionData', so we can retry next time
      }
      
      processedInBatch++;
      
      // Save in batches for safety
      if (processedInBatch >= batchSize) {
        await _saveBatch(i + 1);
        processedInBatch = 0;
      }
      
      // Rate limiting
      await Future.delayed(apiDelay);
    }
    
    // Final save
    if (processedInBatch > 0) {
      await _saveBatch(totalWords);
    }
  }
  
  bool _shouldEnrich(String wordType) {
    const enrichableTypes = {
      'verb',
      'substantiv',
      'adjektiv',
      'pronomen',
    };
    return enrichableTypes.contains(wordType.toLowerCase());
  }
  
  // This function now checks if data is *valid and usable*
  bool _isValidInflectionData(Map<String, dynamic> data) {
    if (data.containsKey('error') || data.containsKey('info') || data.containsKey('status')) {
      return false;
    }
    final analyses = data['analyses'] as Map?;
    if (analyses == null || analyses.isEmpty) {
      return false;
    }
    return true;
  }

  // --- *** NEW FUNCTION: Validate API data *** ---
  // --- *** NEW FIXED FUNCTION *** ---
  bool _validateApiData(Map<String, dynamic> wordEntry, Map<String, dynamic> apiData) {
    // Check noun gender
    if (wordEntry['wordType'] == 'substantiv') {
      try {
        final String correctGenus = wordEntry['genus'] as String; // "mask." or ""
        final String? apiGender = apiData['analyses']?['noun']?['gender']; // "Masculine"

        // --- NEW LOGIC ---
        // Only perform a check if our local data *has* a genus.
        if (correctGenus.isNotEmpty && apiGender != null && apiGender.isNotEmpty) {
          
          // We have a local genus AND an API gender. Now we must compare.
          final String apiGenus = (apiGender == 'Masculine') ? 'mask.'
                                  : (apiGender == 'Feminine') ? 'fem.'
                                  : (apiGender == 'Neuter') ? 'neut.'
                                  : 'unknown';
          
          if (apiGenus != 'unknown' && apiGenus != correctGenus) {
            // This is a REAL conflict (e.g., local "neut." vs API "Feminine")
            print('  ${Colors.red}  → CONFLICT: Local Genus ("$correctGenus") != API Gender ("$apiGender"). Rejecting.${Colors.reset}');
            return false; // REJECT
          }
        }
        // If local genus is empty (""), we accept the API data.
        // If API gender is empty, we accept (nothing to check).
        // If they match, we accept.
        
      } catch (e) {
        // Error parsing, just allow it
      }
    }
    // Data is valid (or not a noun, or passed the checks)
    return true; // ACCEPT by default
  }

  // --- *** NEW FUNCTION: Populate top-level fields *** ---
  void _populateTopLevelFields(Map<String, dynamic> wordEntry, Map<String, dynamic> inflectionData) {
    try {
      // 1. Populate Plural field
      if (wordEntry['wordType'] == 'substantiv' && wordEntry['plural'] == null) {
        final String? pluralForm = inflectionData['analyses']?['noun']?['plural'];
        if (pluralForm != null && pluralForm.isNotEmpty) {
          wordEntry['plural'] = pluralForm;
          print('  ${Colors.green}  → Populated plural: "$pluralForm"${Colors.reset}');
        }
      }

      // 2. (Future) Populate 'forms' for verbs
      // if (wordEntry['wordType'] == 'verb' && wordEntry['forms'] == '') {
      //   // ... logic to get verb forms ...
      // }

    } catch (e) {
      print('  ${Colors.yellow}⚠ Error populating top-level fields: $e${Colors.reset}');
    }
  }
  
  Future<void> _saveBatch(int upToIndex) async {
    print('\n${Colors.cyan}💾 Saving batch (processed $upToIndex/$totalWords words)...${Colors.reset}');
    
    try {
      // Update metadata
      fileManager.updateMetadata('lastEnrichmentRun', DateTime.now().toIso8601String());
      fileManager.updateMetadata('wordsEnriched', successfullyEnriched);
      fileManager.updateMetadata('wordsAlreadyEnriched', alreadyEnriched);
      
      await fileManager.saveAtomic();
      print('${Colors.green}✓ Batch saved successfully${Colors.reset}\n');
    } catch (e) {
      print('${Colors.red}✗ Failed to save batch: $e${Colors.reset}\n');
      throw e;
    }
  }
  
  void printSummary() {
    print('\n${'═' * 70}');
    print('${Colors.bold}📊 ENRICHMENT SUMMARY${Colors.reset}');
    print('═' * 70);
    print('${Colors.cyan}Total words:${Colors.reset}                $totalWords');
    print('${Colors.green}Already enriched:${Colors.reset}         $alreadyEnriched');
    print('${Colors.green}Successfully enriched (new):${Colors.reset}  $successfullyEnriched');
    print('${Colors.red}Failed/Rejected:${Colors.reset}          $failedEnrichment');
    print('${Colors.blue}Skipped (not applicable):${Colors.reset} $skipped');
    print('═' * 70);
    
    final totalEnriched = successfullyEnriched + alreadyEnriched;
    final enrichableWords = totalWords - skipped;
    final percentage = enrichableWords > 0 
        ? (totalEnriched / enrichableWords * 100).toStringAsFixed(1)
        : '0.0';
    
    print('${Colors.bold}Enrichment rate:${Colors.reset} $percentage% ($totalEnriched/$enrichableWords enrichable words)');
    print('═' * 70 + '\n');
  }
}

//============================================================================//
// MAIN
//============================================================================//

Future<void> main(List<String> args) async {
  print('\n${'═' * 70}');
  print('${Colors.bold}🏛️  VOCABULARY INFLECTION ENRICHER (Step 3 of 3)${Colors.reset}');
  print('═' * 70);
  print('${Colors.cyan}Input file:${Colors.reset} $inputFilePath');
  print('${Colors.cyan}Batch size:${Colors.reset} $batchSize words');
  print('${Colors.cyan}API delay:${Colors.reset}  ${apiDelay.inMilliseconds}ms');
  print('═' * 70 + '\n');
  
  final fileManager = VocabularyFileManager(inputFilePath);
  final apiClient = NLPApiClient();
  
  try {
    // Load file
    await fileManager.load();
    
    // Create backup
    await fileManager.createBackup();
    
    // Ask for confirmation
    stdout.write('\n${Colors.yellow}Ready to start API enrichment? (y/n): ${Colors.reset}');
    final response = stdin.readLineSync();
    
    if (response?.toLowerCase() != 'y') {
      print('${Colors.yellow}Enrichment cancelled.${Colors.reset}');
      return;
    }
    
    // Run enrichment
    final enricher = VocabularyEnricher(fileManager, apiClient);
    await enricher.enrich();
    
    // Print summary
    enricher.printSummary();
    
    print('${Colors.green}${Colors.bold}✅ Enrichment completed successfully!${Colors.reset}');
    print('${Colors.cyan}Updated file: $inputFilePath${Colors.reset}\n');
    
  } catch (e, stackTrace) {
    print('${Colors.red}${Colors.bold}❌ FATAL ERROR:${Colors.reset}');
    print('${Colors.red}$e${Colors.reset}');
    print('\n${Colors.yellow}Stack trace:${Colors.reset}');
    print(stackTrace);
    print('\n${Colors.yellow}The file should be intact due to atomic writes.${Colors.reset}');
    print('${Colors.yellow}Check the backup in: $backupDir${Colors.reset}\n');
    exit(1);
  } finally {
    apiClient.dispose();
  }
}