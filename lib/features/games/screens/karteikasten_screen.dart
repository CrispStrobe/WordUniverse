// lib/features/games/screens/karteikasten_screen.dart
//
// Karteikasten-style flashcard view of the SRI database. Five boxes
// (Neu → Gemeistert) projected from the SM-2 state. Players see which
// items are in each box and can manually move them between boxes either
// via a per-item ⋮ menu or by long-pressing and dragging an item card
// onto a target box card.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sri_service.dart';
import '../../../core/theme/space_theme.dart';
import '../providers/game_provider.dart';

class KarteikastenScreen extends StatefulWidget {
  const KarteikastenScreen({super.key});

  @override
  State<KarteikastenScreen> createState() => _KarteikastenScreenState();
}

class _KarteikastenScreenState extends State<KarteikastenScreen> {
  int _selectedBox = 1;

  static const List<({String de, String en, Color color})> _boxes = [
    (de: 'Neu', en: 'New', color: Color(0xFFE57373)),
    (de: 'Erste Festigung', en: 'First Review', color: Color(0xFFFFB74D)),
    (de: 'Übung', en: 'Practice', color: Color(0xFFFFD54F)),
    (de: 'Sicher', en: 'Confident', color: Color(0xFF81C784)),
    (de: 'Gemeistert', en: 'Mastered', color: Color(0xFF64B5F6)),
  ];

  @override
  Widget build(BuildContext context) {
    final sri = context.watch<SriService>();
    final counts = sri.getBoxCounts();
    final itemsInSelected = sri.getItemsInBox(_selectedBox)
      ..sort((a, b) => b.failureCount.compareTo(a.failureCount));

    return Scaffold(
      backgroundColor: SpaceTheme.deepSpace,
      appBar: AppBar(
        title: const Text('Karteikasten'),
        backgroundColor: SpaceTheme.deepSpace,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildBoxRow(counts),
            const Divider(color: Colors.white24, height: 24),
            Expanded(
              child: itemsInSelected.isEmpty
                  ? _buildEmptyState()
                  : _buildItemList(sri, itemsInSelected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoxRow(Map<int, int> counts) {
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 5,
        itemBuilder: (context, i) {
          final boxNum = i + 1;
          final spec = _boxes[i];
          final count = counts[boxNum] ?? 0;
          final selected = boxNum == _selectedBox;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DragTarget<String>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (d) async {
                context.read<GameProvider>().hapticMedium();
                await context
                    .read<SriService>()
                    .moveItemToBox(d.data, boxNum);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text('Karte verschoben nach Box $boxNum – ${spec.de}'),
                    backgroundColor: spec.color.withValues(alpha: 0.85),
                  ),
                );
              },
              builder: (context, candidate, _) {
                final hover = candidate.isNotEmpty;
                return GestureDetector(
                  onTap: () => setState(() => _selectedBox = boxNum),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          spec.color.withValues(alpha: hover ? 1.0 : 0.85),
                          spec.color.withValues(alpha: hover ? 0.85 : 0.55),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white24,
                        width: selected ? 3 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: spec.color.withValues(alpha: 0.4),
                          blurRadius: hover ? 18 : 6,
                          offset: const Offset(2, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Box $boxNum',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          spec.de,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _selectedBox == 5
              ? 'Noch keine gemeisterten Karten in dieser Box.'
              : 'Diese Box ist leer.',
          textAlign: TextAlign.center,
          style: SpaceTheme.bodyStyle.copyWith(color: Colors.white60),
        ),
      ),
    );
  }

  Widget _buildItemList(SriService sri, List<SriLanguageData> items) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final item = items[i];
        return _DraggableItemCard(
          itemId: item.itemId,
          label: _formatItemLabel(item),
          subtitle:
              'EF ${item.easinessFactor.toStringAsFixed(2)} · '
              '${item.successCount}✓ ${item.failureCount}✗',
          currentBox: _selectedBox,
          onMove: (target) => sri.moveItemToBox(item.itemId, target),
        );
      },
    );
  }

  String _formatItemLabel(SriLanguageData item) {
    // itemId is "SKILL_word" — drop the SKILL_ prefix for display, but keep
    // the skill as a small badge prefix so the same word in two skills is
    // distinguishable.
    final underscoreIdx = item.itemId.indexOf('_');
    if (underscoreIdx <= 0 || underscoreIdx >= item.itemId.length - 1) {
      return item.itemId;
    }
    final skill = item.itemId.substring(0, underscoreIdx);
    final word = item.itemId.substring(underscoreIdx + 1);
    return '[$skill] $word';
  }
}

class _DraggableItemCard extends StatelessWidget {
  final String itemId;
  final String label;
  final String subtitle;
  final int currentBox;
  final Future<void> Function(int targetBox) onMove;

  const _DraggableItemCard({
    required this.itemId,
    required this.label,
    required this.subtitle,
    required this.currentBox,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final card = _buildCardBody(context);
    return LongPressDraggable<String>(
      data: itemId,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Opacity(opacity: 0.92, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }

  Widget _buildCardBody(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: ListTile(
        title: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF3E2723),
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF5D4037), fontSize: 12),
        ),
        trailing: PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert, color: Color(0xFF5D4037)),
          tooltip: 'Verschieben',
          onSelected: onMove,
          itemBuilder: (context) => [
            for (var b = 1; b <= 5; b++)
              PopupMenuItem<int>(
                value: b,
                enabled: b != currentBox,
                child: Row(
                  children: [
                    Text(
                      'Box $b',
                      style: TextStyle(
                        fontWeight: b == currentBox
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (b == currentBox)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text('(jetzt)',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
