# 🚀 Word Universe (Wort-Universum)

A space-themed Flutter application designed to help primary school students (Grades 1-6) learn German vocabulary, spelling, and grammar in an engaging way.

## ✨ About The Project

Word Universe turns vocabulary and grammar practice into a space adventure. Built with Flutter, this app is designed for young learners, particularly those in German primary school. It moves beyond simple flashcards by incorporating mini-games, progress tracking, and an adaptive learning system to make learning effective and fun.

The core of the app is a **Spaced Repetition (SRI) service** that tracks a student's performance on a per-word, per-skill basis. This allows the games to intelligently present words that the user struggles with more frequently, ensuring a truly personalized learning path.

## 🎮 Features

  * **Multi-Language Support:** Fully localized for both English (`en`) and German (`de`) users.
  * **Adaptive Learning:** A custom **Spaced Repetition (SRI) Service** (`SriService`) tracks user performance on spelling and grammar, prioritizing new and difficult words.
  * **Persistent Progress:** All user progress (score, level, achievements, SRI data) is saved locally using `shared_preferences`.
  * **Rich Vocabulary:** Loads a comprehensive vocabulary list (`grundwortschatz.json`) into a `VocabularyService`, complete with word types, articles, and common misspellings.
  * **Monetization Ready:** Includes a `PurchaseService` using `in_app_purchase` to handle unlocking a full version.
  * **Parental Gate:** Protects in-app purchases with a simple math question to ensure parent approval.
  * **Developer Debug Panel:** A hidden debug menu (activated by tapping the app title 7 times) allows for forcing IAP unlocks and testing.

### Mini-Games Included:

1.  **Space Word Rescue (`space_word_rescue_game.dart`)**
      * **Skill:** Spelling & Recognition
      * **Gameplay:** A word is shown and spoken. It then disappears, and the user must type it correctly from memory before the timer runs out. It correctly identifies and provides feedback on common graphematic mistakes.
2.  **Galaxy Word-Find (`word_find_game.dart`)**
      * **Skill:** Word Recognition
      * **Gameplay:** A classic word search grid. The user finds hidden vocabulary words by dragging over the letters. The word list is populated based on the user's SRI profile.
3.  **Word Type Station (`word_sort_game.dart`)**
      * **Skill:** Grammar (Wortarten)
      * **Gameplay:** The user is presented with a word (e.g., "Stock") and must drag-and-drop it into the correct category bin (Nomen, Verben, or Adjektive).

## 🛠️ Tech Stack

  * **Framework:** Flutter
  * **Language:** Dart
  * **State Management:** `provider` (with `ChangeNotifierProvider`)
  * **Core Services:**
      * `GameProvider`: Manages the overall game state (score, level, achievements).
      * `SriService`: Manages the spaced repetition logic.
      * `VocabularyService`: Loads and provides all vocabulary data from JSON.
      * `ProgressService`: Handles saving/loading state to storage.
      * `PurchaseService`: Manages in-app purchases.
      * `AudioService`: A wrapper for sound and music playback (placeholder).
  * **Storage:** `shared_preferences` for key-value pair persistence.
  * **Localization:** `flutter_localizations` with `.arb` files.

## 🏁 Getting Started

To run this project locally, follow these steps:

1.  **Clone the repository:**
    ```sh
    git clone [your-repo-url]
    cd voc
    ```
2.  **Install dependencies:**
    ```sh
    flutter pub get
    ```
3.  **Generate localization files:**
      * If you are on the `stable` channel of Flutter, this is often done automatically.
      * If you modify any files in `lib/l10n/`, you must run the localization tool:
    <!-- end list -->
    ```sh
    flutter gen-l10n
    ```
4.  **Run the app:**
    ```sh
    flutter run
    ```
    *Note: The app is configured to force landscape mode via `main.dart`.*

## 📁 Project Structure

The project follows a feature-first architecture.

```
lib/
├── core/                   # Shared services, models, and config
│   ├── config/             # App-wide config (e.g., IAP switch)
│   ├── models/             # Data models (GermanWord, SkillCategory)
│   ├── services/           # Core logic (SriService, VocabService, etc.)
│   └── theme/              # SpaceTheme.dart
│
├── features/               # Individual screens/features
│   ├── achievements/
│   ├── games/              # All mini-game logic
│   │   ├── constants/
│   │   ├── data/           # The all-important vocabulary JSON
│   │   ├── logic/          # Game logic (e.g., WordSearchGenerator)
│   │   ├── models/         # Game-specific models
│   │   ├── providers/      # GameProvider
│   │   ├── screens/        # The game UI files
│   │   └── widgets/
│   ├── home/               # The main dashboard/home screen
│   └── settings/           # The settings screen
│
├── generated/              # Auto-generated l10n files (S.dart)
│
├── l10n/                   # Localization .arb files (app_en.arb, app_de.arb)
│
├── shared/                 # Widgets shared across features
│   ├── utils/
│   └── widgets/            # ParentalGate, PurchaseDialog
│
└── main.dart               # App entry point, provider setup, and routing
```

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.