import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../generated/l10n.dart'; // Import S
import '../../games/providers/game_provider.dart';

class GradeSelector extends StatelessWidget {
  const GradeSelector({super.key});

  // This method MUST be inside the build method or receive context
  String _getGradeDescription(BuildContext context, int grade) {
    final s = S.of(context)!;
    switch (grade) {
      case 3:
        return s.grade3Desc;
      case 4:
        return s.grade4Desc;
      case 5:
        return s.grade5Desc;
      case 6:
        return s.grade6Desc;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2D3E),
                Color(0xFF1E2235),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.school,
                    color: Color(0xFFFFD700), // starYellow
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context)!.chooseYourGrade,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [3, 4, 5, 6].map((grade) {
                  final isSelected = gameProvider.grade == grade;
                  
                  return GestureDetector(
                    onTap: () => gameProvider.setGrade(grade),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFFFFD700), // starYellow
                                  Color(0xFFFF6B35), // planetOrange
                                ],
                              )
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF1A1A2E), // deepSpace
                                  Color(0xFF16213E), // nebulaPurple
                                ],
                              ),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFFD700) // starYellow
                              : const Color(0xFFC0C0C0).withOpacity(0.3), // moonSilver
                          width: 2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          grade.toString(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                _getGradeDescription(context, gameProvider.grade), // Call the method here
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}