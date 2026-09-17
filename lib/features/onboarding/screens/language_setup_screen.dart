import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/language_pack.dart';
import '../../../core/theme/space_theme.dart';

/// Language choices are independent of learner onboarding and DB availability.
class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen(
      {super.key,
      required this.prefs,
      required this.onLocaleChanged,
      required this.onComplete});
  final SharedPreferences prefs;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onComplete;

  static bool isComplete(SharedPreferences prefs) =>
      prefs.getBool('language_setup_complete') == true ||
      (kLanguagePacks.containsKey(prefs.getString('learning_language')) &&
          const ['en', 'de'].contains(prefs.getString('language')));

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  late String learning;
  late String interface;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    learning =
        widget.prefs.getString('learning_language') ?? kDefaultLanguageCode;
    if (!kLanguagePacks.containsKey(learning)) learning = kDefaultLanguageCode;
    interface = widget.prefs.getString('language') ?? 'en';
    if (!const ['en', 'de'].contains(interface)) interface = 'en';
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (!await widget.prefs.setString('learning_language', learning) ||
          !await widget.prefs.setString('language', interface) ||
          !await widget.prefs.setBool('language_setup_complete', true)) {
        throw StateError('Could not save language choices');
      }
      widget.onLocaleChanged(Locale(interface));
      if (mounted) widget.onComplete();
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final de = interface == 'de';
    return Scaffold(
      backgroundColor: SpaceTheme.spaceBlue,
      body: DecoratedBox(
        key: const Key('language-setup-background'),
        decoration: const BoxDecoration(gradient: SpaceTheme.spaceGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SpaceTheme.deepSpace.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: SpaceTheme.starYellow.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_stories,
                          color: SpaceTheme.starYellow, size: 36),
                      const SizedBox(height: 12),
                      Text(
                          de
                              ? 'Willkommen im WortUniversum'
                              : 'Welcome to Word Universe',
                          style:
                              SpaceTheme.headlineStyle.copyWith(fontSize: 28)),
                      const SizedBox(height: 24),
                      _legend(
                        de
                            ? 'Welche Sprache möchtest du lernen?'
                            : 'What language do you want to learn?',
                        de
                            ? 'Sprache für Wörter, Übungen und Spiele.'
                            : 'Language for words, exercises and games.',
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('learning-language'),
                        initialValue: learning,
                        isExpanded: true,
                        style:
                            SpaceTheme.bodyStyle.copyWith(color: Colors.white),
                        dropdownColor: SpaceTheme.nebulaPurple,
                        iconEnabledColor: SpaceTheme.starYellow,
                        decoration: _fieldDecoration(
                            de ? 'Lernsprache' : 'Learning language',
                            Icons.school_outlined),
                        items: [
                          for (final p in orderedLanguagePacks)
                            DropdownMenuItem(
                                value: p.code, child: Text(p.nativeName))
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() => learning = value!),
                      ),
                      const SizedBox(height: 24),
                      _legend(
                        de
                            ? 'Welche Sprache soll die App verwenden?'
                            : 'What language should the app use?',
                        de
                            ? 'Sprache für Menüs, Schaltflächen und Anleitungen.'
                            : 'Language for menus, buttons and instructions.',
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('interface-language'),
                        initialValue: interface,
                        isExpanded: true,
                        style:
                            SpaceTheme.bodyStyle.copyWith(color: Colors.white),
                        dropdownColor: SpaceTheme.nebulaPurple,
                        iconEnabledColor: SpaceTheme.starYellow,
                        decoration: _fieldDecoration(
                            de
                                ? 'Sprache der Oberfläche'
                                : 'Interface language',
                            Icons.translate),
                        items: const [
                          DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                          DropdownMenuItem(value: 'en', child: Text('English'))
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                setState(() => interface = value!);
                                widget.onLocaleChanged(Locale(value!));
                              },
                      ),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(error!,
                                style: SpaceTheme.bodyStyle
                                    .copyWith(color: SpaceTheme.planetOrange))),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const Key('save-languages'),
                          style: SpaceTheme.primaryButtonStyle,
                          onPressed: saving ? null : save,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(de ? 'Weiter' : 'Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(String title, String description) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true,
              child: Text(title,
                  style: SpaceTheme.titleStyle
                      .copyWith(fontSize: 18, color: SpaceTheme.starYellow))),
          const SizedBox(height: 6),
          Text(description, style: SpaceTheme.bodyStyle.copyWith(fontSize: 14)),
          const SizedBox(height: 16),
        ],
      );

  InputDecoration _fieldDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: SpaceTheme.bodyStyle.copyWith(color: SpaceTheme.moonSilver),
        prefixIcon: Icon(icon, color: SpaceTheme.starYellow),
        filled: true,
        fillColor: SpaceTheme.spaceBlue,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SpaceTheme.moonSilver)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: SpaceTheme.starYellow, width: 2)),
      );
}
