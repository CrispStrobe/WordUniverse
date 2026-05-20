// lib/shared/widgets/privacy_policy_dialog.dart
//
// Datenschutzerklärung — kurz, ehrlich, auf Deutsch. Die App speichert
// alle Daten nur lokal auf dem Gerät. Kein Telemetrie-Versand, keine
// Analytics, kein Tracking. Crash-Logs bleiben lokal und werden nur
// dann geteilt, wenn die Nutzerin sie ausdrücklich kopiert.
//
// Strings inline auf Deutsch: voc ist German-first (siehe i18n
// policy in PLAN.md).

import 'package:flutter/material.dart';

import '../../core/theme/space_theme.dart';

class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SpaceTheme.deepSpace,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      color: SpaceTheme.starYellow, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Datenschutz',
                      style: SpaceTheme.headlineStyle.copyWith(fontSize: 22),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              const Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8),
                      _PolicySection(
                        title: 'In Kürze',
                        body:
                            'Diese App speichert den Lernfortschritt deines '
                            'Kindes ausschließlich auf diesem Gerät. Es '
                            'werden keine Daten an Server gesendet. Es gibt '
                            'kein Tracking, keine Werbung, keinen Account, '
                            'keine personenbezogenen Daten — niemals.',
                      ),
                      _PolicySection(
                        title: 'Was wird wo gespeichert',
                        body:
                            'Nur lokal auf diesem Gerät, in den Standard-'
                            'SharedPreferences von Flutter und einer '
                            'Logdatei im sandboxed App-Verzeichnis:\n\n'
                            '• Spielfortschritt (Punktzahl, aktuelles '
                            'Level pro Spiel, freigeschaltete Erfolge)\n'
                            '• Lernkurven-Status (welche Wörter / Items '
                            'wie oft und wie sicher beantwortet wurden)\n'
                            '• Kognitives Profil (Versuche und Treffer '
                            'pro Skill-Bereich)\n'
                            '• Streak (laufende und längste Serie an '
                            'aufeinanderfolgenden Spieltagen)\n'
                            '• Einstellungen (Klassenstufe, Sprache, Ton '
                            'an/aus, Schriftart, eigene Vokabel-Sets)\n'
                            '• Eltern-PIN (4-stellig, für die '
                            'Eltern-Übersicht)\n'
                            '• Eine rollierende Crash-Logdatei mit max. '
                            '50 Einträgen, nur bei tatsächlichen Abstürzen\n\n'
                            'Keiner dieser Werte identifiziert dein Kind. '
                            'Kein Name, keine E-Mail, kein Geburtsdatum, '
                            'keine Geräte-ID, keine IP-Adresse wird '
                            'gespeichert oder übertragen.',
                      ),
                      _PolicySection(
                        title: 'Netzwerk',
                        body:
                            'Die App ruft von sich aus keine externen '
                            'Server auf. Die Wortschatzdatenbank wird beim '
                            'Installieren mitgeliefert und beim ersten '
                            'Start einmalig lokal entpackt — sie wird '
                            'nicht aus dem Netz nachgeladen.\n\n'
                            'Externe Links (z.B. zur Webseite des '
                            'Herausgebers im Impressum) öffnen sich im '
                            'System-Browser. Innerhalb der App passiert '
                            'kein Datenversand.',
                      ),
                      _PolicySection(
                        title: 'Crash-Berichte',
                        body:
                            'Wenn die App abstürzt, wird ein kurzer '
                            'technischer Eintrag (Fehlermeldung, Stacktrace) '
                            'in eine lokale Datei geschrieben. Du kannst '
                            'sie unter Einstellungen → Diagnose ansehen. '
                            'Sie verlässt das Gerät nur, wenn du den Log '
                            'aktiv über "In Zwischenablage kopieren" '
                            'rauskopierst und z.B. in eine E-Mail einfügst.',
                      ),
                      _PolicySection(
                        title: 'Kinder (DSGVO Art. 8 / COPPA)',
                        body:
                            'Diese App ist für Grundschulkinder gedacht. '
                            'Sie ist bewusst so konzipiert, dass die '
                            'Einwilligungsvorschriften der DSGVO-K '
                            '(Artikel 8 in Deutschland) und COPPA (USA) '
                            'gar nicht erst greifen müssen: Es werden '
                            'keinerlei personenbezogene Daten erhoben oder '
                            'verarbeitet. Wir sammeln nichts — es gibt '
                            'nichts, dem zugestimmt werden müsste.',
                      ),
                      _PolicySection(
                        title: 'Deine Rechte',
                        body:
                            'Du kannst alle lokal gespeicherten Daten '
                            'jederzeit über Einstellungen → "Alle Daten '
                            'löschen" entfernen. Damit werden alle oben '
                            'genannten Werte gelöscht. Beim Deinstallieren '
                            'der App entfernen iOS und Android die '
                            'gesamten Sandbox-Daten automatisch.',
                      ),
                      _PolicySection(
                        title: 'Änderungen',
                        body:
                            'Sollten wir je beginnen, Daten zu sammeln '
                            '(z.B. für ein Cloud-Backup), wird diese '
                            'Erklärung aktualisiert, die Änderungen werden '
                            'beim nächsten App-Start hervorgehoben, und '
                            'jede neue Erhebung erfolgt nur mit deiner '
                            'aktiven Zustimmung (Opt-in).',
                      ),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SpaceTheme.titleStyle
                .copyWith(fontSize: 16, color: SpaceTheme.starYellow),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: SpaceTheme.bodyStyle.copyWith(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
