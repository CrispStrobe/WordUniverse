// lib/features/games/tuning.dart
//
// Centralized tuning constants for the progression / mastery / SRI systems.
// Everything in this file is intended to be A/B-testable: changing a value
// here should change behavior across the whole app consistently.

/// Number of consecutive wins at the current level required before the
/// player advances to the next one.
const int kWinsRequiredForLevelUp = 3;

/// Default pass threshold (0.0 to 1.0) for ratio-based outcomes.
const double kDefaultPassThreshold = 0.7;

/// Minimum attempts at a (skill, difficulty) pair before we trust the
/// success ratio enough to claim mastery.
const int kMinAttemptsForMastery = 5;

/// Mastery gate: minimum tracked items before claiming overall mastery.
const int kMinTrackedItemsForMastery = 10;

// --- SM-2 spaced repetition constants ---
const double kSm2InitialEasiness = 2.5;
const double kSm2MinimumEasiness = 1.3;
const double kSm2MasteryEasinessThreshold = 4.0;
const int kSm2MinimumRepetitionsForMastery = 3;
const int kSm2MaxFailuresForMastery = 1;
