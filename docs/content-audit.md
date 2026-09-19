# Auditing what the games actually ask

A learner meets this app as a few hundred generated questions. Whether those
questions are *sound* — answerable, correctly keyed, fairly distracted,
age-appropriate — is not something the test suite can assert, and playing the
games one round at a time surfaces a handful of items an hour.

`test/audit/challenge_dump_test.dart` prints them instead, in bulk, as text or
JSON, so a reviewer or an agent can read hundreds at once.

```sh
# everything reachable, English pack, 25 items per game
WU_DUMP=all WU_DUMP_COUNT=25 flutter test test/audit/challenge_dump_test.dart

# one game, a particular grade band, as JSON lines for a script to check
WU_DUMP=homophone_drill WU_DUMP_GRADE=4 WU_DUMP_FORMAT=json \
  flutter test test/audit/challenge_dump_test.dart

# the German pack (a download, so point at a decompressed copy)
WU_DUMP=all WU_DUMP_LANG=de WU_PACK_DE=/path/to/grundwortschatz.db \
  WU_DUMP_OUT=/tmp/dump_de.txt flutter test test/audit/challenge_dump_test.dart
```

| variable | meaning |
|---|---|
| `WU_DUMP` | `all`, or a comma-separated list of generators |
| `WU_DUMP_COUNT` | items per generator (default 20) |
| `WU_DUMP_GRADE` | grade band to generate for (default 3) |
| `WU_DUMP_LANG` | `en` (default) or `de` |
| `WU_DUMP_FORMAT` | `text` (default) or `json` — one JSON object per line |
| `WU_DUMP_SEED` | RNG seed, so a review is reproducible (default 1) |
| `WU_DUMP_OUT` | write to a file instead of stdout |

It asserts nothing. The output is the product: each item shows the prompt, the
options, which option is keyed correct, and the data behind it.

## What it found on its first run

- **Word of the day walked the dictionary.** The index was the date seed itself
  and the pool arrives in catalogue order, so consecutive days gave consecutive
  entries: *complicated, compound, compromise, con, concentrate, concentration,
  concept, concern, concerned, concerning, concerns…* through January, and
  *Lexikon, lila, Limonade, Lineal, links, Lippe, Lob…* in German. Fixed by
  scattering the seed; the word for a given day is still the same for everyone.
- **Inflected forms were offered as headwords**, and noun plurals still took a
  singular article from `displayName` — "an elements", "a laughs", "an arms".
  Fixed by restricting the pool to entries whose spelling is their own lemma.
- Both were invisible to the test suite and to ordinary play, and obvious
  within seconds of reading a dump.

## Coverage, and how to widen it

All 31 games in the menu are reachable: every one builds its challenges in a
service under `lib/features/games/services/`, and the screen only draws what
the service returns. A run ends with the generator count, and names any game
that is not reachable — today none are.

Keep it that way when adding a game: put the challenge construction in a
service that takes data and returns data, and register it in the `generators`
map in `test/audit/challenge_dump_test.dart`. A game whose challenges are built
inside its widget cannot be reviewed except by playing it.

Several games share one service — `cloze_service.dart` backs cloze, expression
and proverb; `adaptive_word_selection.dart` backs six practice games; the SRI
review game reuses `definition_quiz_service.dart` so both inherit the same
fairness rules (headword redaction, no name glosses, article-labelled options).
A fix in one is a fix in all of them, which is the point.
