import 'dart:convert'; // For jsonEncode, jsonDecode, utf8, base64Decode
import 'dart:async'; // For Completer and Stream processing
import 'dart:io'; // For creating files and directories
import 'package:http/http.dart' as http; // For making HTTP requests
import 'dart:developer' as dev; // For clearer, named logging
import 'dart:math'; // For max()

//----------------------------------------------------------------------------//
// CONFIGURATION
//----------------------------------------------------------------------------//

const String postUrl =
    'https://cstr-spacy-de.hf.space/gradio_api/call/get_morphology';
const String getUrlBase =
    'https://cstr-spacy-de.hf.space/gradio_api/call/get_morphology/';
const String outputDir = './api_results'; // Directory for saved visuals

class SpacyApiClient {
  final http.Client _client;
  bool _isDisposed = false;

  SpacyApiClient() : _client = http.Client();

  void dispose() {
    _isDisposed = true;
    _client.close();
    dev.log('API Client disposed.', name: 'SpacyApiClient');
  }

  //==========================================================================//
  //
  // 📜 INSTRUCTIONAL GUIDE: THE GRADIO 2-STEP STREAMING API
  //
  // Our Hugging Face Space uses Gradio's streaming API, which relies on
  // Server-Sent Events (SSE). This is an asynchronous, two-step process.
  //
  // 1. POST: First, you "enqueue" a job. You send a POST request with
  //    your inputs. The server *immediately* responds with a unique
  //    "event_id". It does NOT send the result yet.
  //
  // 2. GET: Second, you "listen" for the result. You open a streaming GET
  //    request to an endpoint using that `event_id`. The server holds this
  //    connection open and sends you "events" as they happen (like
  //    'heartbeat', 'generating', and finally 'complete').
  //
  // This test script implements this exact 2-step flow.
  //
  //==========================================================================//

  Future<void> runTest({
    required String testId, // Used for file naming
    required String uiLang,
    required String modelLangKey,
    required String text,
    bool saveVisuals = false, // The new CLI flag
  }) async {
    if (_isDisposed) {
      throw StateError('Client is disposed. Cannot run test.');
    }

    // Use print for user-facing status, dev.log for debug-level info
    print('🚀 STARTING TEST ($testId): Model=$modelLangKey, Text="$text"');
    print('-' * 70);

    try {
      // --- STEP 1: POST for Event ID ---
      final eventId = await _step1_postForEventId(
        uiLang: uiLang,
        modelLangKey: modelLangKey,
        text: text,
      );
      print('✅ STEP 1 (POST) successful. Event ID: $eventId');
      print('Waiting for stream...');

      // --- STEP 2: GET Stream Results ---
      final outputs = await _step2_getStreamResults(eventId);
      print('✅ STEP 2 (Stream "complete") successful.');

      // --- STEP 3: Print Interpreted Results ---
      _printInterpretedResults(
        outputs,
        testId: testId,
        saveVisuals: saveVisuals,
      );
    } catch (e, stackTrace) {
      // Use dev.log to get the full stack trace for errors
      dev.log(
        '❌ TEST FAILED ($testId)',
        name: 'SpacyApiClient',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      print('=' * 70 + '\n');
    }
  }

  Future<String> _step1_postForEventId({
    required String uiLang,
    required String modelLangKey,
    required String text,
  }) async {
    final payload = jsonEncode({
      "data": [
        uiLang,
        modelLangKey,
        text,
      ]
    });

    final postResponse = await _client.post(
      Uri.parse(postUrl),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );

    if (postResponse.statusCode != 200) {
      throw Exception(
          'STEP 1 (POST) FAILED: Status ${postResponse.statusCode}, Body: ${postResponse.body}');
    }

    final postBody = jsonDecode(postResponse.body);
    if (postBody is! Map || !postBody.containsKey('event_id')) {
      throw Exception(
          'STEP 1 (POST) FAILED: Response did not contain "event_id". Body: ${postResponse.body}');
    }

    return postBody['event_id'] as String;
  }

  Future<List<dynamic>> _step2_getStreamResults(String eventId) async {
    final getRequest = http.Request('GET', Uri.parse(getUrlBase + eventId));
    getRequest.headers['Accept'] = 'text/event-stream';
    getRequest.headers['Cache-Control'] = 'no-cache';

    final streamedResponse = await _client.send(getRequest);

    if (streamedResponse.statusCode != 200) {
      throw Exception(
          'STEP 2 (GET) FAILED: Status ${streamedResponse.statusCode}');
    }

    final completer = Completer<List<dynamic>>();
    String buffer = '';
    bool isComplete = false;

    // Start listening to the stream of data
    streamedResponse.stream.transform(utf8.decoder).listen(
      (chunk) {
        if (isComplete) return; // Stop processing if already done
        buffer += chunk; // Add new data to the buffer

        int messageEndIndex;
        while ((messageEndIndex = buffer.indexOf('\n\n')) != -1) {
          if (isComplete) break;
          final message = buffer.substring(0, messageEndIndex);
          buffer = buffer.substring(messageEndIndex + 2);

          final result = _parseSseMessage(message);
          if (result != null) {
            isComplete = true;
            completer.complete(result); // Complete the Future
            break;
          }
        }
      },
      onError: (e, stackTrace) {
        if (!isComplete) {
          isComplete = true;
          completer.completeError(
              Exception('STEP 2 (Stream) FAILED: $e'), stackTrace);
        }
      },
      onDone: () {
        if (!isComplete) {
          isComplete = true;
          completer.completeError(
              Exception('STEP 2 (Stream) FAILED: Stream ended prematurely.'));
        }
      },
    );

    return completer.future; // Return the Future we will complete later
  }

  List<dynamic>? _parseSseMessage(String messageBlock) {
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
        final decodedData = jsonDecode(eventData);
        if (decodedData is List) {
          return decodedData; // This is our successful result!
        } else {
          throw Exception('Final data was not a List as expected.');
        }
      } catch (e) {
        throw Exception('Could not decode final JSON data. Error: $e');
      }
    }

    if (eventType == 'error') {
      throw Exception('Stream returned an "error" event: $eventData');
    }
    return null;
  }

  //==========================================================================//
  //
  // 🎨 RESULT INTERPRETATION & PRETTY-PRINTING
  //
  // This section parses the API output to create a clean,
  // human-readable summary.
  //
  //==========================================================================//

  /// Parses all outputs and prints a clean summary to the console.
  void _printInterpretedResults(List<dynamic> outputs,
      {required String testId, required bool saveVisuals}) {
    if (outputs.length < 4) {
      print('⚠️ Warning: Expected 4+ outputs but got ${outputs.length}');
      return;
    }

    // --- Output 0: DataFrame ---
    print('\n--- 📊 MORPHOLOGICAL & SYNTACTIC ANALYSIS ---');
    _printTableFromData(outputs[0]);

    // --- Output 2: Dependency Parse HTML ---
    print('\n--- 🌳 DEPENDENCY PARSE VISUALIZATION ---');
    _printHtmlSummary(
      outputs[2] as String? ?? '',
      isDepParse: true,
      saveVisuals: saveVisuals,
      savePath: '$outputDir/${testId}_dep_parse.svg',
    );

    // --- Output 3: Named Entities (NER) HTML ---
    print('\n--- 🏷️ NAMED ENTITY RECOGNITION (NER) ---');
    _printHtmlSummary(
      outputs[3] as String? ?? '',
      isDepParse: false,
      saveVisuals: saveVisuals,
      savePath: '$outputDir/${testId}_ner.html',
    );
  }

  /// Helper to print a well-formatted ASCII table from the DataFrame output.
  void _printTableFromData(dynamic tableOutput) {
    if (tableOutput == null || tableOutput is! Map) {
      print('  (Invalid table data received)');
      return;
    }

    final Map<String, dynamic> tableData = Map<String, dynamic>.from(tableOutput);

    final headers = (tableData['headers'] as List? ?? []).cast<String>();
    final data = (tableData['data'] as List? ?? [])
        .map((row) => (row as List).map((cell) => cell.toString()).toList())
        .toList();

    if (headers.isEmpty || data.isEmpty) {
      print('  (No analysis data returned)');
      return;
    }

    // 1. Calculate column widths
    final colWidths = List<int>.filled(headers.length, 0);
    for (int i = 0; i < headers.length; i++) {
      colWidths[i] = headers[i].length;
    }
    for (final row in data) {
      for (int i = 0; i < row.length; i++) {
        colWidths[i] = max(colWidths[i], row[i].length);
      }
    }

    // 2. Create border strings
    String rowSeparator = '+';
    String headerSeparator = '+';
    for (final width in colWidths) {
      rowSeparator += '${'-' * (width + 2)}+';
      headerSeparator += '${'=' * (width + 2)}+';
    }

    // 3. Print table
    print(rowSeparator);
    String headerRow = '|';
    for (int i = 0; i < headers.length; i++) {
      headerRow += ' ${headers[i].padRight(colWidths[i])} |';
    }
    print(headerRow);
    print(headerSeparator);

    for (final row in data) {
      String dataRow = '|';
      for (int i = 0; i < row.length; i++) {
        dataRow += ' ${row[i].padRight(colWidths[i])} |';
      }
      print(dataRow);
    }
    print(rowSeparator);
  }

  /// Helper to parse the visualization HTML and print a clean summary.
  void _printHtmlSummary(
    String html, {
    required bool isDepParse,
    bool saveVisuals = false,
    String? savePath,
  }) {
    // Regex to find <p> tags (for errors/info)
    final pTagRegex = RegExp(r"<p.*?>(.*?)</p>", dotAll: true);
    // Regex to find NER <mark> tags
    final nerRegex = RegExp(
      r'<mark.*?>(.*?)<span.*?>(.*?)</span>.*?</mark>',
      dotAll: true,
      caseSensitive: false,
    );
    // Regex to find the Base64-encoded SVG
    final svgRegex = RegExp(r'src="data:image/svg\+xml;base64,(.*?)"');

    final pMatch = pTagRegex.firstMatch(html);

    if (pMatch != null) {
      // It's an info or error message
      final message = pMatch.group(1)!.trim();
      if (html.contains('color: orange;')) {
        print('  ⚠️ $message');
      } else {
        print('  ℹ️ $message');
      }
      return;
    }

    // If it's not a <p> tag, handle based on type
    if (isDepParse) {
      // Check for the Base64 SVG image, not a literal <svg> tag
      final svgMatch = svgRegex.firstMatch(html);
      if (svgMatch != null) {
        String status =
            '  ✅ Dependency Parse SVG generated.\n     (This is a visual chart; all textual data is in the table above)';
        
        if (saveVisuals && savePath != null) {
          try {
            final base64Data = svgMatch.group(1)!;
            final svgString = utf8.decode(base64Decode(base64Data));
            File(savePath).writeAsStringSync(svgString);
            status = '  ✅ Dependency Parse SVG generated. (Saved to $savePath)';
          } catch (e) {
            status = '  ✅ Dependency Parse SVG generated. (Error saving file: $e)';
          }
        } else {
            status = '  ✅ Dependency Parse SVG generated. (Pass --save-visuals to save file)';
        }
        print(status);

      } else {
        print('  (No dependency parse data returned)');
      }
    } else {
      // It's NER, let's extract the entities
      final matches = nerRegex.allMatches(html);
      if (matches.isEmpty) {
        print('  ℹ️ No entities found.');
        return;
      }

      print('  ✨ Entities Found:');
      for (final match in matches) {
        // Clean up whitespace and newlines from the entity text
        final text = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        final label = match.group(2)!.trim();
        print('    • ${text.padRight(20)} ($label)');
      }

      // Save the NER HTML if requested
      if (saveVisuals && savePath != null) {
        try {
          File(savePath).writeAsStringSync(html);
          print('     (Visual HTML saved to $savePath)');
        } catch (e) {
          print('     (Error saving NER HTML: $e)');
        }
      }
    }
  }
}

/// Main function to run all our tests.
///
/// You can optionally pass a command-line argument to save the visual files:
///
/// dart ./test_spacy_api.dart --save-visuals
///
Future<void> main(List<String> args) async {
  // Check for the --save-visuals flag
  final bool saveVisuals = args.contains('--save-visuals');

  if (saveVisuals) {
    try {
      Directory(outputDir).createSync(recursive: true);
      print('📂 Saving visual results to $outputDir');
    } catch (e) {
      print('FATAL: Could not create directory $outputDir. Error: $e');
      return;
    }
  }

  final api = SpacyApiClient();

  try {
    // Test 1: English
    await api.runTest(
      testId: 'test_1_en',
      uiLang: 'EN',
      modelLangKey: 'en',
      text: 'Apple is looking at buying U.K. startup for \$1 billion.',
      saveVisuals: saveVisuals,
    );

    // Test 2: German
    await api.runTest(
      testId: 'test_2_de',
      uiLang: 'DE',
      modelLangKey: 'de',
      text: 'Angela Merkel war Bundeskanzlerin von Deutschland.',
      saveVisuals: saveVisuals,
    );

    // Test 3: Spanish
    await api.runTest(
      testId: 'test_3_es',
      uiLang: 'ES',
      modelLangKey: 'es',
      text: 'El rápido zorro marrón salta sobre el perro perezoso.',
      saveVisuals: saveVisuals,
    );

    // Test 4: Ancient Greek
    await api.runTest(
      testId: 'test_4_grc_proiel',
      uiLang: 'EN',
      modelLangKey: 'grc-proiel-trf',
      text: 'μῆνιν ἄειδε θεὰ Πηληïάδεω Ἀχιλῆos',
      saveVisuals: saveVisuals,
    );

    // Test 5: Ancient Greek (NER)
    await api.runTest(
      testId: 'test_5_grc_ner',
      uiLang: 'EN',
      modelLangKey: 'grc_ner_trf',
      text: 'Παῦλος δοῦλος Ἰησοῦ Χριστοῦ, κλητὸς ἀπόστοLOS',
      saveVisuals: saveVisuals,
    );

    // Test 6: Empty Text
    await api.runTest(
      testId: 'test_6_empty',
      uiLang: 'EN',
      modelLangKey: 'en',
      text: '   ', // Empty or whitespace
      saveVisuals: saveVisuals,
    );
  } catch (e) {
    dev.log('A critical error occurred in main.',
        name: 'main', error: e);
  } finally {
    // CRITICAL: Always close the client when you are done.
    api.dispose();
  }
}