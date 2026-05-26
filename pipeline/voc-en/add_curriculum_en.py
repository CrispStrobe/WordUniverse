"""Tag EN DB entries with curriculum source tags (Cambridge YLE, DE primary school).

Sources (all word lists are factual data, not copyrightable expression):
  - Cambridge Young Learners English (YLE) Starters/Movers/Flyers vocabulary lists
    Published by Cambridge Assessment English; included here as factual word lists.
  - German primary school English curriculum (Grundschule Klasse 3-4, 2024)
    Based on common vocabulary expected in German DE Lehrplan for English.
    Words represent facts (pedagogical requirements), not copyrightable expression.

Tags added (cumulative — a Starters word also gets Movers/Flyers tags):
  source:cambridge_yle_starters   (A1 level, ~300 words)
  source:cambridge_yle_movers     (A1-A2, ~450 additional)
  source:cambridge_yle_flyers     (A2, ~700 additional)
  source:de_curriculum_en         (DE Grundschule 3-4 English target vocabulary)

Also sets metadata_json["yle_level"] = "starters" | "movers" | "flyers" for the
lowest YLE level at which the word appears.

Usage:
  python add_curriculum_en.py [--db grundwortschatz_en.db] [--no-compress] [--dry-run]
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
DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_curriculum_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"


# ---------------------------------------------------------------------------
# Cambridge YLE Starters vocabulary (~300 core words, A1)
# Source: Cambridge Assessment English YLE Starters word list (published curriculum)
# ---------------------------------------------------------------------------
YLE_STARTERS: set[str] = {
    "a", "afternoon", "all", "am", "an", "and", "animal", "answer",
    "apple", "are", "at", "aunt", "away",
    "bag", "ball", "banana", "bath", "bedroom", "big", "bird",
    "black", "blue", "book", "box", "boy", "bread", "brown", "bus",
    "cake", "can", "cat", "chair", "child", "class", "clean", "clock",
    "clothes", "colour", "color", "come", "computer", "cow", "crayon", "cup",
    "day", "desk", "dirty", "doctor", "dog", "doll", "door", "draw",
    "drink", "duck",
    "ear", "eat", "egg", "elephant", "evening", "eye",
    "family", "farm", "father", "fish", "floor", "flower", "fly", "food",
    "friend", "frog", "fruit",
    "get", "giraffe", "girl", "go", "good", "grass", "great", "green",
    "grey", "gray", "guitar",
    "hair", "hand", "happy", "have", "he", "head", "hear", "hello",
    "help", "her", "here", "his", "home", "horse", "house", "how",
    "hungry",
    "I", "i", "in", "is", "it", "its",
    "jump",
    "kite", "know",
    "leg", "lemon", "like", "listen", "little", "look", "love", "lunch",
    "make", "man", "me", "milk", "morning", "mother", "mouth", "my",
    "name", "new", "nice", "night", "no", "nose", "not", "now", "number",
    "of", "old", "on", "orange", "our", "out",
    "paper", "parrot", "pen", "pencil", "pink", "play", "please", "pool",
    "purple", "put",
    "rabbit", "read", "red", "ride", "robot", "room", "run",
    "school", "see", "she", "sheep", "sister", "sit", "small", "snake",
    "sock", "spell", "sport", "stand", "star", "stop", "swim",
    "table", "take", "talk", "tea", "teacher", "that", "the", "their",
    "them", "there", "this", "tiger", "to", "toy", "tree",
    "uncle", "up",
    "walk", "wall", "water", "we", "what", "where", "which", "white",
    "window", "with", "woman", "write",
    "yellow", "yes", "you", "your",
    "zebra", "zero",
}

# ---------------------------------------------------------------------------
# Cambridge YLE Movers vocabulary (~450 additional words beyond Starters, A1-A2)
# ---------------------------------------------------------------------------
YLE_MOVERS: set[str] = {
    "afraid", "after", "again", "agree", "air", "airport", "almost", "alone",
    "already", "also", "always", "angry", "another", "any", "arm", "arrive",
    "art", "ask", "asleep",
    "back", "bad", "balloon", "bat", "beach", "bean", "bear", "because",
    "bed", "before", "behind", "below", "beside", "best", "better", "between",
    "bicycle", "bike", "body", "bored", "bottle", "bowl", "break", "bridge",
    "bright", "bring", "brother", "build", "busy", "butter", "butterfly", "buy",
    "camera", "camp", "car", "care", "carry", "catch", "chicken", "chocolate",
    "cinema", "city", "climb", "close", "cloud", "coffee", "cold", "comic",
    "corner", "correct", "country", "cousin", "cross", "cut",
    "dance", "dark", "daughter", "decide", "deep", "different", "difficult",
    "dinner", "direction", "down", "dream", "dress", "drive",
    "each", "early", "earth", "easy", "email", "enough", "everyone",
    "everything", "exciting", "expensive",
    "fall", "famous", "fast", "fat", "feel", "fell", "few", "field", "find",
    "first", "fix", "follow", "forest", "forget", "fork", "front", "full",
    "game", "garage", "gate", "give", "glad", "glasses", "goat", "ground",
    "group", "grow", "guess",
    "hat", "healthy", "hedge", "helicopter", "hill", "hit", "hobby", "hold",
    "holiday", "honey", "hop", "hospital", "hotel", "huge", "hunt", "hurry",
    "hurt",
    "ice", "idea", "important", "island",
    "job", "join",
    "kangaroo", "keep", "kind", "kitchen", "knife", "knock",
    "lake", "language", "large", "late", "laugh", "leaf", "learn", "left",
    "letter", "library", "light", "line", "lion", "long",
    "machine", "map", "match", "meal", "meat", "meet", "might", "minute",
    "miss", "mix", "monkey", "mountain", "move", "music", "must",
    "need", "never", "next", "noisy", "nothing", "nurse",
    "often", "once", "only", "open", "opposite", "outside", "over",
    "page", "pair", "park", "party", "past", "path", "pattern", "pear",
    "pet", "phone", "picnic", "picture", "pilot", "pizza", "place", "plant",
    "plate", "playground", "pleased", "pocket", "police", "pond", "pour",
    "prize", "problem", "pull", "push",
    "queen", "quick",
    "race", "radio", "rain", "rainbow", "ready", "really", "remember", "rest",
    "rice", "rich", "ring", "road", "round", "rule",
    "sad", "sandwich", "say", "sea", "seat", "send", "sentence", "shop",
    "short", "show", "sick", "side", "silly", "sing", "size", "ski", "sky",
    "slide", "slow", "smile", "snow", "someone", "somebody", "soon", "sorry",
    "sort", "sound", "soup", "space", "spend", "station", "stick", "story",
    "street", "strong", "study", "sugar", "sun", "sunny", "supermarket",
    "surprised", "sweet",
    "tail", "tall", "team", "telephone", "tent", "test", "think", "throw",
    "ticket", "tired", "today", "together", "tomorrow", "top", "touch",
    "town", "train", "try", "turn",
    "under", "until", "use",
    "village", "visit",
    "wait", "warm", "wash", "watch", "week", "weekend", "well", "wet",
    "wind", "winner", "wonder", "work", "world", "worry", "wrong",
    "year", "yesterday",
}

# ---------------------------------------------------------------------------
# Cambridge YLE Flyers vocabulary (~700 additional words beyond Movers, A2)
# ---------------------------------------------------------------------------
YLE_FLYERS: set[str] = {
    "above", "accident", "act", "adult", "adventure", "age", "ahead",
    "alien", "along", "although", "ambulance", "ancient", "announcement",
    "anywhere", "appear", "area", "army", "around", "article", "artist",
    "astronaut", "athlete", "attend", "audience", "autumn", "award",
    "awesome",
    "balcony", "ballet", "band", "bank", "barbecue", "bark", "bathroom",
    "battery", "battle", "beak", "believe", "belong", "billion", "blind",
    "board", "boat", "bother", "breath", "building",
    "calm", "candle", "captain", "cartoon", "cave", "ceiling", "century",
    "channel", "character", "charity", "chess", "chief", "chimney",
    "coast", "collect", "comfortable", "company", "competition", "consider",
    "continue", "costume", "crash", "creative", "crowded",
    "daily", "danger", "deadline", "decision", "defend", "delicious",
    "describe", "desperate", "determine", "disagree", "discover", "discuss",
    "distance", "dizzy", "document", "dolphin", "double", "download",
    "drum",
    "earthquake", "emergency", "emotion", "energy", "enormous", "entrance",
    "environment", "escape", "excellent", "exercise", "expect", "experience",
    "expert", "explain", "explore", "extreme",
    "fail", "fair", "faith", "familiar", "fantasy", "fashion", "fee",
    "fence", "festival", "fierce", "final", "float", "flood", "fog",
    "force", "fossil", "freeze", "frighten", "future",
    "generous", "gentle", "ghost", "giant", "government", "graceful",
    "grand", "grateful", "guard", "guide",
    "harbor", "harbour", "hardworking", "headline", "height", "heritage",
    "hero", "highlight", "historic", "history", "homemade", "honest",
    "however", "human", "humour", "humor",
    "illegal", "imagine", "immediately", "incredible", "information",
    "injure", "insect", "instrument", "interview", "investigate",
    "invitation",
    "journey", "judge",
    "launch", "layer", "lazy", "lead", "lecture", "limit", "local", "loud",
    "magic", "magnificent", "manage", "mayor", "medical", "middle",
    "mission", "model", "museum", "mystery",
    "natural", "nervous", "notice",
    "ocean", "offer", "opinion", "opportunity", "ordinary", "organize",
    "outdoor", "overnight",
    "pain", "painting", "palace", "partner", "pause", "perfect", "perform",
    "permission", "photograph", "planet", "plastic", "poem", "point",
    "popular", "possible", "prepare", "president", "prevent", "primary",
    "private", "produce", "profession", "protest", "proud", "public",
    "puzzle",
    "realize", "recipe", "recycle", "reduce", "reflect", "region",
    "regular", "repair", "report", "rescue", "respect", "responsible",
    "result", "retire", "reward", "roof", "rough",
    "satellite", "scenery", "secret", "series", "service", "shadow",
    "shape", "sharp", "shelter", "silence", "solution", "speech", "speed",
    "spirit", "staff", "stage", "strange", "stretch", "struggle", "subject",
    "succeed", "success", "suggest", "sunrise", "survive", "sustainable",
    "symbol",
    "talent", "technology", "terrible", "tiny", "tourist", "tradition",
    "transport", "treasure", "treatment", "trial", "trouble", "trust",
    "truth",
    "underground", "unique", "university", "unusual", "urgent",
    "valley", "various", "victim", "victory", "voice", "volcano",
    "volunteer", "voyage",
    "wealth", "wildlife", "wise", "witness",
    "youth",
}

# ---------------------------------------------------------------------------
# German DE Grundschule 3-4 English target vocabulary
# Based on Lehrplan Plus Bayern + common cross-state EN curriculum vocabulary.
# These are pedagogical facts (target-vocabulary lists), not copyrightable.
# ---------------------------------------------------------------------------
DE_CURRICULUM_EN: set[str] = {
    # Numbers
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty",
    "first", "second", "third",
    # Colors
    "red", "blue", "green", "yellow", "orange", "purple", "pink", "black",
    "white", "brown", "grey", "gray",
    # Animals
    "dog", "cat", "bird", "fish", "horse", "cow", "pig", "duck", "rabbit",
    "mouse", "snake", "lion", "elephant", "tiger", "giraffe", "zebra", "frog",
    "chicken", "sheep", "spider", "bee", "butterfly",
    # Family
    "mother", "father", "sister", "brother", "grandmother", "grandfather",
    "aunt", "uncle", "baby", "family", "parents",
    # School
    "school", "teacher", "book", "pen", "pencil", "ruler", "rubber", "eraser",
    "bag", "desk", "chair", "class", "classroom", "board", "lesson",
    # Food and drink
    "apple", "banana", "bread", "butter", "cake", "cheese", "chicken",
    "chocolate", "egg", "fish", "fruit", "hamburger", "juice", "milk",
    "orange", "pizza", "salad", "sandwich", "soup", "water", "potato",
    "vegetable", "yoghurt", "yogurt",
    # Body
    "arm", "back", "ear", "eye", "face", "foot", "feet", "hair", "hand",
    "head", "leg", "mouth", "nose", "tooth", "teeth", "stomach",
    # Clothes
    "coat", "dress", "hat", "jacket", "jeans", "shirt", "shoes", "skirt",
    "socks", "trousers", "pants", "gloves", "scarf", "boots",
    # Time
    "day", "week", "month", "morning", "afternoon", "evening", "night",
    "today", "tomorrow", "yesterday", "Monday", "Tuesday", "Wednesday",
    "Thursday", "Friday", "Saturday", "Sunday",
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December",
    "spring", "summer", "autumn", "winter",
    # Places
    "home", "house", "school", "park", "shop", "store", "town", "village",
    "street", "road", "garden", "bedroom", "kitchen", "bathroom", "living room",
    "playground",
    # Greetings and classroom language
    "hello", "goodbye", "please", "thank you", "yes", "no", "sorry",
    "excuse me", "help", "good morning", "good afternoon", "good evening",
    "how are you", "fine", "great", "ok",
    # Core verbs
    "be", "can", "come", "do", "drink", "eat", "fly", "get", "give", "go",
    "have", "hear", "jump", "know", "like", "listen", "live", "look", "love",
    "make", "play", "put", "read", "ride", "run", "say", "see", "sing",
    "sit", "sleep", "speak", "stand", "swim", "take", "talk", "tell",
    "think", "understand", "walk", "want", "watch", "write",
    # Core adjectives
    "big", "clean", "cold", "dirty", "fast", "good", "great", "happy",
    "hard", "hot", "little", "long", "new", "nice", "old", "short", "small",
    "soft", "tall", "young",
    # Classroom objects
    "computer", "phone", "crayon", "paper", "box", "ball", "toy",
    # Countries and languages (common in DE curriculum)
    "England", "Germany", "France", "America", "English", "German", "French",
    # Weather
    "sun", "rain", "snow", "wind", "cloud", "hot", "cold", "warm", "sunny",
    "rainy", "cloudy",
    # Sports and hobbies
    "sport", "football", "soccer", "basketball", "swimming", "running",
    "dancing", "singing", "reading", "drawing", "music", "guitar",
    # Transport
    "car", "bus", "train", "bike", "bicycle", "plane",
    # Common adjectives for DE Klasse 3-4
    "funny", "clever", "kind", "friendly", "beautiful", "ugly", "loud", "quiet",
    # Prepositions and connectors
    "in", "on", "under", "over", "next", "between", "behind", "in front of",
    "and", "but", "because", "with",
}

# Normalize: all lowercase for matching
_YLE_STARTERS_LOWER    = {w.lower() for w in YLE_STARTERS}
_YLE_MOVERS_LOWER      = {w.lower() for w in YLE_MOVERS}
_YLE_FLYERS_LOWER      = {w.lower() for w in YLE_FLYERS}
_DE_CURRICULUM_LOWER   = {w.lower() for w in DE_CURRICULUM_EN}

# Combined sets for each tier
_ALL_YLE = _YLE_STARTERS_LOWER | _YLE_MOVERS_LOWER | _YLE_FLYERS_LOWER

TAG_STARTERS   = "source:cambridge_yle_starters"
TAG_MOVERS     = "source:cambridge_yle_movers"
TAG_FLYERS     = "source:cambridge_yle_flyers"
TAG_DE_CURRIC  = "source:de_curriculum_en"


def yle_level(word_lower: str) -> str | None:
    if word_lower in _YLE_STARTERS_LOWER:
        return "starters"
    if word_lower in _YLE_MOVERS_LOWER:
        return "movers"
    if word_lower in _YLE_FLYERS_LOWER:
        return "flyers"
    return None


def yle_tags(word_lower: str) -> list[str]:
    """Return all YLE tags applicable (starters ⊂ movers ⊂ flyers in practice)."""
    tags = []
    if word_lower in _YLE_STARTERS_LOWER:
        tags.append(TAG_STARTERS)
    if word_lower in _YLE_MOVERS_LOWER or word_lower in _YLE_STARTERS_LOWER:
        tags.append(TAG_MOVERS)
    if word_lower in _ALL_YLE:
        tags.append(TAG_FLYERS)
    return tags


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",          default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run",     action="store_true")
    ap.add_argument("--overwrite",   action="store_true",
                    help="Re-tag even if yle_level already set in metadata_json")
    args = ap.parse_args()

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    rows = con.execute(
        "SELECT id, word, lemma, metadata_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in rows]
    print(f"Loaded {len(rows)} DB entries")

    yle_counts    = {"starters": 0, "movers": 0, "flyers": 0, "none": 0}
    de_curric_count = 0
    updated = 0
    skipped = 0

    for r in rows:
        meta = json.loads(r["metadata_json"] or "{}")

        if not args.overwrite and meta.get("yle_level"):
            skipped += 1
            continue

        word  = (r.get("word")  or "").strip().lower()
        lemma = (r.get("lemma") or "").strip().lower()

        lvl = yle_level(word) or (yle_level(lemma) if lemma and lemma != word else None)
        new_tags_for_word = yle_tags(word)
        if lemma and lemma != word:
            for t in yle_tags(lemma):
                if t not in new_tags_for_word:
                    new_tags_for_word.append(t)

        is_de_curric = word in _DE_CURRICULUM_LOWER or (lemma and lemma != word and lemma in _DE_CURRICULUM_LOWER)

        if not lvl and not is_de_curric:
            yle_counts["none"] += 1
            continue

        tags: list[str] = list(meta.get("tags") or [])

        if lvl:
            meta["yle_level"] = lvl
            yle_counts[lvl] += 1
            for t in new_tags_for_word:
                if t not in tags:
                    tags.append(t)

        if is_de_curric:
            de_curric_count += 1
            if TAG_DE_CURRIC not in tags:
                tags.append(TAG_DE_CURRIC)

        if not lvl:
            yle_counts["none"] += 1

        meta["tags"] = tags

        if not args.dry_run:
            con.execute(
                "UPDATE words SET metadata_json = ? WHERE id = ?",
                (json.dumps(meta, ensure_ascii=False), r["id"]),
            )
        updated += 1

    if not args.dry_run:
        con.commit()
    con.close()

    print(f"Updated:   {updated}")
    print(f"Skipped (already tagged): {skipped}")
    print("YLE level distribution:")
    for lvl in ["starters", "movers", "flyers"]:
        print(f"  {lvl}: {yle_counts[lvl]}")
    print(f"Not in YLE lists: {yle_counts['none']}")
    print(f"DE curriculum matches: {de_curric_count}")

    if not args.dry_run:
        print(f"Copying {WORK_DB} → {src_db}")
        shutil.copy2(WORK_DB, src_db)
        if not args.no_compress and DB_GZ.exists():
            print(f"Compressing → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
