# 🚀 Word Universe (Wort-Universum)

A space-themed Flutter application for practising German and English vocabulary, spelling, and grammar through games.

## ✨ About The Project

Word Universe turns vocabulary and grammar practice into a space adventure. It is designed for learners with different ages and backgrounds, including students, independent adult learners, and adults learning German as a foreign or second language (DaF/DaZ). It moves beyond simple flashcards by combining mini-games, progress tracking, and an adaptive learning system.

The selectable vocabulary levels are broad difficulty bands. They help sequence content, but they do not correspond strictly to school years, age groups, or CEFR levels.

The core of the app is a **Spaced Repetition (SRI) service** that tracks performance on a per-word, per-skill basis. This allows the games to present difficult words more frequently and adapt practice to the learner. A short onboarding flow captures the learning language, goal, starting band, and preferred daily practice time; the home screen then offers a three-step daily learning plan.

## 🎮 Features

  * **Multi-Language Support:** Fully localized for both English (`en`) and German (`de`) users.
  * **Adaptive Learning:** A custom **Spaced Repetition (SRI) Service** (`SriService`) tracks user performance on spelling and grammar, prioritizing new and difficult words.
  * **Persistent Progress:** All user progress (score, level, achievements, SRI data) is saved locally using `shared_preferences`.
  * **Guided Daily Practice:** Goal-based sessions combine review, a focused exercise, and words in context.
  * **Game Discovery:** Search, skill filters, recommendations, favourites, and recent games make the larger catalogue easier to navigate.
  * **Focus Mode:** Reduces decorative motion and keeps learning actions prominent.
  * **Rich Vocabulary:** Loads a comprehensive vocabulary list (`grundwortschatz.json`) into a `VocabularyService`, complete with word types, articles, and common misspellings.
  * **Monetization Deferred:** Purchase infrastructure remains in the codebase, but IAP is disabled while the core learning experience is refined.
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

*(…plus more than 30 mini-games in total. The menu filters by the chosen learning language.)*

### English-only games (learning language = English):

  * **Homophone Drill / Word Trap** (`homophone_drill_game.dart`) — pick the right spelling for the context (hear/here, affect/effect).
  * **Phrasal Verb Power** (`phrasal_verb_power_game.dart`) — pick the particle that completes a sentence (*Please ___ your toys* → put **away**).
  * **Phrasal Verb Match** (`phrasal_verb_match_game.dart`) — pick a phrasal verb's meaning; distractors are real meanings of other phrasal verbs.
  * **False Friends** (`false_friends_game.dart`) — pick what an English word *really* means; the German look-alike is the trap (gift ≠ Gift).

    The phrasal-verb games use a `phrasal_verbs` table (Wiktionary CC-BY-SA + LLM grade-leveled examples; `pipeline/voc-en/add_phrasal_verbs_en.py`); False Friends uses a curated `false_friends` table.

### German-only games (learning language = German):

  * **Wortfalle** (`wortfalle_game.dart`) — German confusables drill: pick the right word in a sentence (das/dass, Wal/Wahl, isst/ist, Kirsche/Kirche). 64 curated pairs (Wiktionary homophones CC-BY-SA + LanguageTool confusion sets).
  * …plus the German falling-tile games (compound builder, capitalisation, separable verbs) and the shared flash games.

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

This project uses a dual-license model — see [DATA_LICENSE.md](DATA_LICENSE.md) for the full breakdown:

- **Application code** (`lib/`, platform directories) — proprietary, all rights reserved.
- **German vocabulary database** (`assets/grundwortschatz.db.gz`) — **GNU GPL-3.0**: it bundles childLex (GPL-3.0) age-band norms, and GPL-3.0 content cannot be redistributed under CC-BY-SA-4.0 (one-way compatible), so the combined DE DB is GPL-3.0. Redistribution: [cstr/grundwortschatz-voc-de](https://huggingface.co/datasets/cstr/grundwortschatz-voc-de).
- **English vocabulary database** (`assets/grundwortschatz_en.db.gz`) — **CC BY-SA 4.0**, inherited from upstream sources (Wiktionary, ConceptNet, OEWN, and others). Redistribution: [cstr/grundwortschatz-voc-en](https://huggingface.co/datasets/cstr/grundwortschatz-voc-en).
- **Pipeline scripts** (`pipeline/`) — MIT License.

Full attribution for every data source is shown in the in-app **Settings → Licenses** screen.
## Deploying

Push to `main` → GitHub Actions builds the Flutter web app, runs analyze + tests,
and deploys to Vercel production (aliased to `wortuniversum.vercel.app`). The
`VERCEL_TOKEN` repo secret authenticates the deploy; Vercel's native Git
integration is intentionally disconnected so Actions is the sole deployer.
