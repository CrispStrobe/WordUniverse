import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/language_pack.dart';
import '../../core/services/language_pack_service.dart';
import '../../core/theme/space_theme.dart';

class AiContentLabels {
  const AiContentLabels(this.language);
  final String language;
  bool get _de => language == 'de';

  String get title =>
      _de ? 'KI-unterstützte Lerninhalte' : 'AI-assisted learning content';
  String get packDisclosure => _de
      ? 'Einige Beispielsätze und Erklärungen in diesem Sprachpaket wurden mit KI erzeugt oder überarbeitet. Sie können Fehler enthalten. Für ältere Inhalte sind Anbieter und Modell nicht immer dokumentiert.'
      : 'Some example sentences and definitions in this language pack were generated or revised using AI. They can contain mistakes. Provider and model details are not always recorded for older content.';
  String get entryDisclosure => _de
      ? 'Für diesen Eintrag sind KI-Beiträge dokumentiert. Das bedeutet nicht, dass alle Felder mit KI erstellt oder von Menschen geprüft wurden.'
      : 'AI contributions are recorded for this entry. This does not mean every field was AI-generated or reviewed by a person.';
  String get unknownDetails => _de
      ? 'Genauere Angaben zur Herkunft fehlen bei älteren Inhalten.'
      : 'Detailed origin records may be unavailable for older content.';
}

/// A pack-level disclosure describes its mixed corpus, not each individual word.
class AiLearningContentNotice extends StatelessWidget {
  const AiLearningContentNotice({super.key, this.language, this.entry = false});
  final String? language;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    final labels = AiContentLabels(
        language ?? Localizations.localeOf(context).languageCode);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(labels.title,
                style: const TextStyle(
                    color: SpaceTheme.moonSilver,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            const SizedBox(height: 4),
            Text(entry ? labels.entryDisclosure : labels.packDisclosure,
                style: const TextStyle(
                    color: SpaceTheme.moonSilver, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Keeps the pack disclosure reachable while a learner is playing a game.
class ActivePackAiContentInfo extends StatelessWidget {
  const ActivePackAiContentInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LanguagePackService?>();
    final pack =
        languagePackFor(service?.activeLanguage ?? kDefaultLanguageCode);
    if (pack?.containsAiAssistedContent != true) return const SizedBox.shrink();
    final labels =
        AiContentLabels(Localizations.localeOf(context).languageCode);
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: SpaceTheme.moonSilver,
      ),
      label: Text(labels.title, style: const TextStyle(fontSize: 12)),
      icon: const Icon(Icons.info_outline,
          size: 20, color: SpaceTheme.moonSilver),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels.title),
          content: Text(labels.packDisclosure),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            )
          ],
        ),
      ),
    );
  }
}

/// Describes recorded contributions without attributing untouched source fields.
class AiEntryContentNotice extends StatelessWidget {
  const AiEntryContentNotice({super.key, required this.aiContent});
  final Map<String, dynamic> aiContent;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final labels = AiContentLabels(language);
    final de = language == 'de';
    final fields = aiContent['fields'];
    final records = fields is Map ? fields.entries.toList() : [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AiLearningContentNotice(entry: true),
        if (records.isEmpty)
          Text(labels.unknownDetails,
              style:
                  const TextStyle(color: SpaceTheme.moonSilver, fontSize: 12)),
        for (final entry in records)
          if (entry.value is Map) ...[
            Text(_describe(entry.key.toString(), entry.value as Map, de),
                style: const TextStyle(
                    color: SpaceTheme.moonSilver, fontSize: 12)),
            const SizedBox(height: 4),
          ],
      ],
    );
  }

  String _describe(String path, Map record, bool de) {
    final field = path.contains('definitions')
        ? (de ? 'Erklärung' : 'Definition')
        : path.contains('examples')
            ? (de ? 'Beispiele' : 'Examples')
            : (de ? 'Inhalt' : 'Content');
    final origin = record['origin'] == 'ai_generated'
        ? (de ? 'mit KI erzeugt' : 'AI-generated')
        : record['origin'] == 'ai_assisted_revision'
            ? (de ? 'mit KI überarbeitet' : 'AI-assisted revision')
            : (de ? 'Herkunft unbekannt' : 'origin unrecorded');
    final generation = record['generation'];
    final parts = ['$field: $origin'];
    if (generation is Map) {
      final host = generation['provider_host'];
      if (host is String && host.isNotEmpty) {
        parts.add(switch (host) {
          'configured_endpoint' =>
            de ? 'Konfigurierter Endpunkt' : 'Configured endpoint',
          'local_endpoint' => de ? 'Lokaler Endpunkt' : 'Local endpoint',
          _ => host,
        });
      }
      final response = generation['response_model'];
      final requested = generation['requested_model'];
      if (response is String && response.isNotEmpty) {
        parts.add('${de ? 'Antwortmodell' : 'Response model'}: $response');
      } else if (requested is String && requested.isNotEmpty) {
        parts.add(
            '${de ? 'Angefragtes Modell' : 'Requested model'}: $requested');
      }
    }
    if (record['details_status'] != 'recorded') {
      parts.add(
          de ? 'Herkunftsdetails unvollständig' : 'origin details incomplete');
    }
    return parts.join(' · ');
  }
}
