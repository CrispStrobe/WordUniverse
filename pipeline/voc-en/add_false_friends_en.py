#!/usr/bin/env python3
"""Add a curated DE↔EN false-friends table to the EN vocabulary DB.

False friends ("falsche Freunde") are English words that look/sound like a
German word but mean something different — the classic trap for German
learners of English (gift ≠ Gift, become ≠ bekommen, ...).

The data is a hand-curated catalogue of common, correct, age-appropriate
pairs (the raw Wikipedia/Wiktionary lists contain errors, obscure terms, and
vulgar entries unsuitable for a K-6+ app). Pairs are factual; the reference
source is Wikipedia "Liste falscher Freunde" (CC-BY-SA 4.0) — same license as
the EN DB, so no license change.

Each row keys on the ENGLISH word (the learner is in EN mode) and is linked to
its `words` row when present (`word_id`, nullable). Stored in a `false_friends`
table; idempotent rebuild.

Fields per pair:
  english        the English word                       e.g. "gift"
  german         the German look-alike                   e.g. "Gift"
  english_means  German gloss of the English word        e.g. "Geschenk"
  german_means   English gloss of the German word        e.g. "poison"
  example        short English sentence using it right   (optional)

Usage:
  python3 add_false_friends_en.py --load [--compress]
"""
from __future__ import annotations

import argparse
import gzip
import json
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SRC_DB = HERE / "grundwortschatz_en.db"
DB_GZ = REPO / "assets" / "grundwortschatz_en.db.gz"

# english, german, english_means (DE), german_means (EN), example
FALSE_FRIENDS: list[tuple[str, str, str, str, str]] = [
    ("gift", "Gift", "Geschenk", "poison", "She gave me a birthday gift."),
    ("become", "bekommen", "werden", "to receive / get", "He wants to become a teacher."),
    ("also", "also", "auch", "so / therefore", "I like tea, and also coffee."),
    ("actual", "aktuell", "tatsächlich, eigentlich", "current, up-to-date", "The actual cost was higher than planned."),
    ("art", "Art", "Kunst", "type, kind, manner", "She studies modern art."),
    ("brave", "brav", "mutig", "well-behaved", "The brave firefighter saved the cat."),
    ("chef", "Chef", "Koch / Köchin", "boss", "The chef cooked a delicious meal."),
    ("eventually", "eventuell", "schließlich, am Ende", "possibly, maybe", "We waited, and eventually the bus came."),
    ("fabric", "Fabrik", "Stoff, Gewebe", "factory", "This shirt is made of soft fabric."),
    ("fast", "fast", "schnell", "almost", "The car is very fast."),
    ("handy", "Handy", "praktisch, griffbereit", "mobile phone", "A small torch is handy when camping."),
    ("kind", "Kind", "nett, freundlich", "child", "It was very kind of you to help."),
    ("sensible", "sensibel", "vernünftig", "sensitive", "Wear sensible shoes for the long walk."),
    ("sympathetic", "sympathisch", "mitfühlend", "likeable, nice", "She was sympathetic when I felt sad."),
    ("billion", "Billion", "Milliarde", "trillion (10¹²)", "The company is worth a billion dollars."),
    ("boot", "Boot", "Stiefel", "boat", "Put on your boots; it is muddy."),
    ("brand", "Brand", "Marke", "fire / blaze", "Which brand of cereal do you like?"),
    ("caution", "Kaution", "Vorsicht", "deposit, bail", "Use caution when crossing the road."),
    ("critic", "Kritik", "Kritiker(in)", "criticism, review", "The film critic wrote a great review."),
    ("decent", "dezent", "anständig", "discreet, subtle", "He did a decent job on the test."),
    ("familiar", "familiär", "bekannt, vertraut", "family-related, intimate", "Her face looked familiar to me."),
    ("genial", "genial", "freundlich, heiter", "brilliant, ingenious", "He greeted us with a genial smile."),
    ("gymnasium", "Gymnasium", "Turnhalle", "grammar school", "We play basketball in the gymnasium."),
    ("lecture", "Lektüre", "Vorlesung", "reading (material)", "The professor gave a long lecture."),
    ("meaning", "Meinung", "Bedeutung", "opinion", "What is the meaning of this word?"),
    ("note", "Note", "Notiz, Anmerkung", "grade / musical note", "I left a note on the fridge."),
    ("ordinary", "ordinär", "gewöhnlich, normal", "vulgar, crude", "It was just an ordinary Monday."),
    ("pension", "Pension", "Rente", "guesthouse, B&B", "He lives on a small pension now."),
    ("rat", "Rat", "Ratte", "advice / council", "A rat ran across the floor."),
    ("see", "See", "sehen", "lake / sea", "I can see the mountains from here."),
    ("spend", "spenden", "ausgeben (Geld/Zeit)", "to donate", "I spend my pocket money on books."),
    ("stadium", "Stadium", "Stadion", "stage, phase", "The football stadium was full."),
    ("tablet", "Tablett", "Tablette / Tablet", "tray", "She read the news on her tablet."),
    ("will", "will", "Zukunftsform (wird)", "want (ich will)", "I will help you tomorrow."),
    ("bald", "bald", "kahl, glatzköpfig", "soon", "My uncle is going bald."),
    ("mist", "Mist", "Nebel, Dunst", "manure / nonsense", "Morning mist covered the field."),
    ("rock", "Rock", "Fels, Stein", "skirt", "They climbed the steep rock."),
    ("blame", "blamieren", "die Schuld geben", "to embarrass / disgrace", "Do not blame me for the mistake."),
    ("fee", "Fee", "Gebühr", "fairy", "The entrance fee is five euros."),
    ("eagle", "Igel", "Adler", "hedgehog", "An eagle soared above the cliff."),
    ("angel", "Angel", "Engel", "fishing rod", "She dressed as an angel for the play."),
    ("ankle", "Enkel", "Knöchel", "grandchild", "He twisted his ankle while running."),
    ("map", "Mappe", "Landkarte", "folder, portfolio", "We used a map to find the castle."),
    ("mode", "Mode", "Modus, Art", "fashion", "Switch the phone to silent mode."),
    ("serious", "seriös", "ernst", "reputable, respectable", "This is a serious problem."),
    ("sin", "Sinn", "Sünde", "sense, meaning", "Lying is considered a sin."),
    ("tag", "Tag", "Etikett, Anhänger", "day", "Put a name tag on your bag."),
    ("taste", "Taste", "Geschmack", "key, button", "I love the taste of fresh bread."),
    ("wand", "Wand", "Zauberstab", "wall", "The wizard waved his magic wand."),
    ("hose", "Hose", "Schlauch", "trousers", "Water the plants with the garden hose."),
    ("list", "List", "Liste", "cunning, ruse", "Write a list of things to buy."),
    ("receipt", "Rezept", "Quittung, Beleg", "recipe / prescription", "Keep the receipt in case you return it."),
    ("wink", "winken", "zwinkern", "to wave", "She gave me a friendly wink."),
    ("warehouse", "Warenhaus", "Lagerhaus", "department store", "The boxes are stored in the warehouse."),
    ("undertaker", "Unternehmer", "Bestatter", "entrepreneur", "The undertaker arranged the funeral."),
    ("physician", "Physiker", "Arzt / Ärztin", "physicist", "The physician examined the patient."),
    ("pregnant", "prägnant", "schwanger", "concise, succinct", "She is six months pregnant."),
    ("sympathy", "Sympathie", "Mitgefühl", "liking, affinity", "They sent sympathy after the loss."),
    ("paragraph", "Paragraph", "Absatz", "section / § (law)", "Read the first paragraph aloud."),
    ("chips", "Chips", "Pommes frites (BE) / Chips (AE)", "crisps (BE) / fries", "We ate fish and chips."),
    ("coffin", "Koffer", "Sarg", "suitcase", "The pharaoh lay in a stone coffin."),
    ("clean", "klein", "sauber", "small", "Please keep your room clean."),
]

_CREATE = """
CREATE TABLE false_friends (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    word_id INTEGER,
    english TEXT NOT NULL,
    german TEXT NOT NULL,
    english_means TEXT NOT NULL,
    german_means TEXT NOT NULL,
    example TEXT,
    source TEXT,
    license TEXT,
    FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
)
"""


def load(compress: bool) -> int:
    if not SRC_DB.exists():
        sys.exit(f"DB not found: {SRC_DB}")
    con = sqlite3.connect(SRC_DB)
    con.execute("DROP TABLE IF EXISTS false_friends")
    con.execute(_CREATE)
    con.execute("CREATE INDEX IF NOT EXISTS idx_ff_word ON false_friends(word_id)")

    # dedupe by english word; warn on accidental dupes
    seen: set[str] = set()
    linked = 0
    for en, de, en_m, de_m, ex in FALSE_FRIENDS:
        key = en.lower().strip()
        if key in seen:
            print(f"  [skip] duplicate english '{en}'")
            continue
        seen.add(key)
        row = con.execute(
            "SELECT id FROM words WHERE lower(word) = ? ORDER BY id LIMIT 1",
            (key,)).fetchone()
        word_id = row[0] if row else None
        if word_id:
            linked += 1
        con.execute(
            "INSERT INTO false_friends(word_id, english, german, english_means, "
            "german_means, example, source, license) VALUES (?,?,?,?,?,?,?,?)",
            (word_id, en.strip(), de.strip(), en_m, de_m, ex,
             'wikipedia:liste-falscher-freunde', 'CC-BY-SA-4.0'))
    con.commit()
    n = con.execute("SELECT COUNT(*) FROM false_friends").fetchone()[0]
    con.close()
    print(f"loaded {n} false friends ({linked} linked to a words row, "
          f"{n - linked} standalone)")

    if compress:
        print(f"compressing → {DB_GZ}")
        with SRC_DB.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        print(f"  {DB_GZ.stat().st_size // 1024} KB written")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Add false_friends table to EN DB")
    ap.add_argument("--load", action="store_true")
    ap.add_argument("--compress", action="store_true")
    args = ap.parse_args()
    if args.load:
        return load(args.compress)
    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
