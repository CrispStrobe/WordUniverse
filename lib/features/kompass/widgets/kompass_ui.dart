import 'package:flutter/material.dart';
import 'kompass_strings.dart';

const kompassInk = Color(0xFF17304A);
const kompassMuted = Color(0xFF52677D);
const kompassPaper = Color(0xFFF8FAFC);
const kompassNavy = Color(0xFF111E35);
const kompassTeal = Color(0xFF42DDC2);
const kompassGold = Color(0xFFFFD57A);

Color kompassDomainColor(String domain) => switch (domain) {
      'reading' => const Color(0xFF8BC9FF),
      'spelling' => const Color(0xFFFFD57A),
      'language' => const Color(0xFFC6B3FF),
      _ => const Color(0xFF73E7C7),
    };
IconData kompassDomainIcon(String domain) => switch (domain) {
      'reading' => Icons.travel_explore_rounded,
      'spelling' => Icons.spellcheck_rounded,
      'language' => Icons.view_quilt_rounded,
      _ => Icons.route_rounded,
    };

class KompassPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const KompassPage(
      {super.key, required this.title, required this.child, this.actions});
  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: 'SpaceGrotesk',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166A68)),
          scaffoldBackgroundColor: const Color(0xFFF0F4F8),
          appBarTheme: const AppBarTheme(
            backgroundColor: kompassNavy,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
          ),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          )),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          )),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        child: Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: SafeArea(child: child),
        ),
      );
}

class KompassCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  const KompassCard(
      {super.key,
      required this.child,
      this.color = Colors.white,
      this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kompassInk.withValues(alpha: .09))),
        child: child,
      );
}

class KompassBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const KompassBadge(
      {super.key,
      required this.label,
      this.icon,
      this.color = const Color(0xFFE7F2EE)});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(40)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: kompassInk),
            const SizedBox(width: 6)
          ],
          Flexible(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kompassInk))),
        ]),
      );
}

class KompassNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const KompassNotice(
      {super.key,
      required this.text,
      this.icon = Icons.info_outline_rounded,
      this.color = const Color(0xFFE7F0F7)});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 21, color: kompassInk),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: kompassInk, height: 1.45))),
        ]),
      );
}

class KompassEmpty extends StatelessWidget {
  final String title, message;
  final Widget? action;
  const KompassEmpty(
      {super.key, required this.title, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: KompassCard(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined, size: 48, color: kompassMuted),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: kompassInk)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kompassMuted, height: 1.5)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          )),
        ),
      ));
}

class KompassSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const KompassSectionTitle(
      {super.key, required this.title, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: kompassInk)),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(subtitle!,
                      style: const TextStyle(color: kompassMuted, height: 1.4))
                ],
              ])),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      );
}

String kompassDuration(int seconds) {
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

String kompassScoreLabel(KompassStrings s, double earned, double possible,
    {double pending = 0}) {
  final scored = (possible - pending).clamp(0, possible);
  if (pending > 0 && scored == 0) {
    return '${s.pending}: ${kompassPoints(pending)} ${s.points}';
  }
  return '${kompassPoints(earned)} / ${kompassPoints(scored)} ${s.choose('geprüfte Punkte', 'reviewed points')}'
      '${pending > 0 ? ' · ${kompassPoints(pending)} ${s.choose('noch offen', 'pending')}' : ''}';
}

Widget kompassScore(BuildContext context, double earned, double possible,
        {double pending = 0}) =>
    Text(
        kompassScoreLabel(KompassStrings.of(context), earned, possible,
            pending: pending),
        style: const TextStyle(
            fontWeight: FontWeight.bold, color: kompassInk, height: 1.4));
