"""Add curriculum words missing from the EN DB.

Identifies single-word entries from CEFR-J (A1–B2), Cambridge YLE
Starters/Movers/Flyers, and UK DfE statutory Y1-Y6 lists that are not yet in
the vocabulary DB, then inserts them with minimal structure.

After running this script, re-run the enrichment chain to fill data:
  python add_wordfreq_en.py --overwrite --no-compress
  python add_cefr_en.py --overwrite --no-compress
  python add_curriculum_en.py --overwrite --no-compress
  python add_uk_curriculum.py --overwrite --no-compress
  python add_llm_examples_en.py --grade ...   (will pick up new words)

Wiktionary/WordNet enrichment requires re-running 11b_enrich_local.py on the
new entries (or accepting them as definition-free for now).

Usage:
  python add_missing_curriculum_en.py [--db grundwortschatz_en.db] [--dry-run]
                                      [--max-cefr-level A1|A2|B1|B2]
                                      [--no-compress]
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_missing_curriculum_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"
CEFRJ_CSV  = HERE / "sources" / "cefrj-vocabulary-profile-1.5.csv"

CEFR_ORDER = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}

# Cambridge YLE Starters (must have — very basic A1 vocabulary)
YLE_STARTERS = {
    "a","afternoon","all","am","an","animal","answer","apple","are","at","aunt","away",
    "bag","ball","banana","bath","bedroom","big","bird","black","blue","book","box","boy",
    "bread","brown","bus","cake","can","cat","chair","child","class","clean","clock",
    "clothes","colour","color","come","computer","cow","crayon","cup","day","desk","dirty",
    "doctor","dog","doll","door","draw","drink","duck","ear","eat","egg","elephant","evening",
    "eye","family","farm","father","fish","floor","flower","fly","food","friend","frog","fruit",
    "get","giraffe","girl","go","good","grass","great","green","grey","gray","guitar","hair",
    "hand","happy","have","he","head","hear","hello","help","her","here","his","home","horse",
    "house","how","hungry","i","in","is","it","its","jump","kite","know","leg","lemon","like",
    "listen","little","look","love","lunch","make","man","me","milk","morning","mother","mouth",
    "my","name","new","nice","night","no","nose","not","now","number","of","old","on","orange",
    "our","out","paper","parrot","pen","pencil","pink","play","please","pool","purple","put",
    "rabbit","read","red","ride","robot","room","run","school","see","she","sheep","sister",
    "sit","small","snake","sock","spell","sport","stand","star","stop","swim","table","take",
    "talk","tea","teacher","that","the","their","them","there","this","tiger","to","toy","tree",
    "uncle","up","walk","wall","water","we","what","where","which","white","window","with",
    "woman","write","yellow","yes","you","your","zebra","zero",
}

# Cambridge YLE Movers (A1-A2 additional)
YLE_MOVERS = {
    "afraid","after","again","agree","air","airport","almost","alone","already","also",
    "always","angry","another","any","arm","arrive","art","ask","asleep","back","bad",
    "balloon","bat","beach","bean","bear","because","bed","before","behind","below","beside",
    "best","better","between","bicycle","bike","body","bored","bottle","bowl","break","bridge",
    "bright","bring","brother","build","busy","butter","butterfly","buy","camera","camp","car",
    "care","carry","catch","chicken","chocolate","cinema","city","climb","close","cloud",
    "coffee","cold","comic","corner","correct","country","cousin","cross","cut","dance","dark",
    "daughter","decide","deep","different","difficult","dinner","direction","down","dream",
    "dress","drive","each","early","earth","easy","email","enough","everyone","everything",
    "exciting","expensive","fall","famous","fast","fat","feel","fell","few","field","find",
    "first","fix","follow","forest","forget","fork","front","full","game","garage","gate",
    "give","glad","glasses","goat","ground","group","grow","guess","hat","healthy","hedge",
    "helicopter","hill","hit","hobby","hold","holiday","honey","hop","hospital","hotel","huge",
    "hunt","hurry","hurt","ice","idea","important","island","job","join","kangaroo","keep",
    "kind","kitchen","knife","knock","lake","language","large","late","laugh","leaf","learn",
    "left","letter","library","light","line","lion","long","machine","map","match","meal",
    "meat","meet","might","minute","miss","mix","monkey","mountain","move","music","must",
    "need","never","next","noisy","nothing","nurse","often","once","only","open","opposite",
    "outside","over","page","pair","park","party","past","path","pattern","pear","pet","phone",
    "picnic","picture","pilot","pizza","place","plant","plate","playground","pleased","pocket",
    "police","pond","pour","prize","problem","pull","push","queen","quick","race","radio",
    "rain","rainbow","ready","really","remember","rest","rice","rich","ring","road","round",
    "rule","sad","sandwich","say","sea","seat","send","sentence","shop","short","show","sick",
    "side","silly","sing","size","ski","sky","slide","slow","smile","snow","someone","somebody",
    "soon","sorry","sort","sound","soup","space","spend","station","stick","story","street",
    "strong","study","sugar","sun","sunny","supermarket","surprised","sweet","tail","tall",
    "team","telephone","tent","test","think","throw","ticket","tired","today","together",
    "tomorrow","top","touch","town","train","try","turn","under","until","use","village",
    "visit","wait","warm","wash","watch","week","weekend","well","wet","wind","winner",
    "wonder","work","world","worry","wrong","year","yesterday",
}

# Cambridge YLE Flyers (A2 additional)
YLE_FLYERS = {
    "above","accident","act","adult","adventure","age","ahead","alien","along","although",
    "ambulance","ancient","announcement","anywhere","appear","area","army","around","article",
    "artist","astronaut","athlete","attend","audience","autumn","award","awesome","balcony",
    "ballet","band","bank","barbecue","bark","bathroom","battery","battle","beak","believe",
    "belong","billion","blind","board","boat","bother","breath","building","calm","candle",
    "captain","cartoon","cave","ceiling","century","channel","character","charity","chess",
    "chief","chimney","coast","collect","comfortable","company","competition","consider",
    "continue","costume","crash","creative","crowded","daily","danger","deadline","decision",
    "defend","delicious","describe","desperate","determine","disagree","discover","discuss",
    "distance","dizzy","document","dolphin","double","download","drum","earthquake",
    "emergency","emotion","energy","enormous","entrance","environment","escape","excellent",
    "exercise","expect","experience","expert","explain","explore","extreme","fail","fair",
    "faith","familiar","fantasy","fashion","fee","fence","festival","fierce","final","float",
    "flood","fog","force","fossil","freeze","frighten","future","generous","gentle","ghost",
    "giant","government","graceful","grand","grateful","guard","guide","harbor","harbour",
    "hardworking","headline","height","heritage","hero","highlight","historic","history",
    "honest","however","human","humour","humor","illegal","imagine","immediately","incredible",
    "information","injure","insect","instrument","interview","investigate","invitation",
    "journey","judge","launch","layer","lazy","lead","lecture","limit","local","loud","magic",
    "magnificent","manage","mayor","medical","middle","mission","model","museum","mystery",
    "natural","nervous","notice","ocean","offer","opinion","opportunity","ordinary","organize",
    "outdoor","overnight","pain","painting","palace","partner","pause","perfect","perform",
    "permission","photograph","planet","plastic","poem","point","popular","possible","prepare",
    "president","prevent","primary","private","produce","profession","protest","proud","public",
    "puzzle","realize","recipe","recycle","reduce","reflect","region","regular","repair",
    "report","rescue","respect","responsible","result","retire","reward","roof","rough",
    "satellite","scenery","secret","series","service","shadow","shape","sharp","shelter",
    "silence","solution","speech","speed","spirit","staff","stage","strange","stretch",
    "struggle","subject","succeed","success","suggest","sunrise","survive","sustainable",
    "symbol","talent","technology","terrible","tiny","tourist","tradition","transport",
    "treasure","treatment","trial","trouble","trust","truth","underground","unique",
    "university","unusual","urgent","valley","various","victim","victory","voice","volcano",
    "volunteer","voyage","wealth","wildlife","wise","witness","youth",
}

# UK DfE statutory word lists (OGL v3)
UK_Y1_Y2 = {
    "the","a","do","to","today","of","said","says","are","were","was","is","his","has",
    "i","you","your","they","be","he","she","we","me","no","go","so","by","my","here",
    "there","where","love","come","some","one","once","ask","friend","school","put","push",
    "pull","full","house","our","could","would","should","door","floor","poor","because",
    "find","kind","mind","behind","child","children","wild","climb","most","only","both",
    "old","cold","gold","hold","told","every","even","great","break","steak","pretty",
    "beautiful","after","fast","last","past","class","grass","pass","plant","path","bath",
    "hour","move","prove","improve","sure","sugar","eye","water","want","watch","what",
    "why","when","which","who","whole","any","many","again","half","money","people","oh",
    "their","father","christmas",
}

UK_Y3_Y4 = {
    "accident","actually","address","answer","appear","arrive","believe","bicycle","breath",
    "breathe","build","busy","calendar","caught","centre","century","certain","circle",
    "complete","consider","continue","decide","describe","different","difficult","disappear",
    "early","earth","eight","enough","exercise","experience","experiment","extreme","famous",
    "favourite","february","forward","fruit","grammar","group","guard","guide","heard","heart",
    "height","history","imagine","increase","important","interest","island","knowledge",
    "learn","length","library","material","medicine","mention","minute","natural","naughty",
    "notice","occasion","often","opposite","ordinary","particular","peculiar","perhaps",
    "popular","position","possess","possible","potatoes","pressure","probably","promise",
    "purpose","quarter","question","recent","regular","reign","remember","sentence","separate",
    "special","straight","strange","strength","suppose","surprise","therefore","though",
    "thought","through","various","weight","woman","women",
}


def _is_valid_single_word(w: str) -> bool:
    """Exclude multi-word, contracted, or non-alphabetic tokens."""
    if not w or "'" in w or " " in w:
        return False
    if re.search(r'[^a-zA-Z\-]', w):
        return False
    return True


_POS_MAP = {
    "noun": "noun", "verb": "verb", "adjective": "adjective", "adverb": "adverb",
    "determiner": "other", "pronoun": "other", "preposition": "other",
    "conjunction": "other", "interjection": "other", "numeral": "other",
    "article": "other", "abbreviation": "other", "phrase": "other",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",              default=str(DEFAULT_DB))
    ap.add_argument("--no-compress",     action="store_true")
    ap.add_argument("--dry-run",         action="store_true")
    ap.add_argument("--max-cefr-level",  default="B2",
                    choices=["A1","A2","B1","B2","C1","C2"],
                    help="Maximum CEFR level to import (default B2)")
    args = ap.parse_args()

    max_level_order = CEFR_ORDER[args.max_cefr_level]

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    # Build set of all forms currently in DB
    db_forms: set[str] = set()
    for r in con.execute("SELECT word, lemma FROM words"):
        if r["word"]:  db_forms.add(r["word"].lower().strip())
        if r["lemma"]: db_forms.add(r["lemma"].lower().strip())

    # Find max original_id number
    max_id_row = con.execute(
        "SELECT max(cast(substr(original_id,9) as integer)) FROM words "
        "WHERE original_id LIKE 'word_en_%'"
    ).fetchone()
    next_id = (max_id_row[0] or 0) + 1

    # ---- Load CEFR-J ----
    cefrj: dict[str, tuple[str, str]] = {}  # lower_word → (level, pos)
    if CEFRJ_CSV.exists():
        for row in csv.DictReader(CEFRJ_CSV.read_text(encoding="utf-8-sig").splitlines()):
            hw = (row.get("headword") or "").strip()
            level = (row.get("CEFR") or row.get("cefr") or "").strip().upper()
            pos = (row.get("pos") or "").strip().lower()
            if not hw or not level: continue
            for v in hw.split("/"):
                w = v.strip()
                if not _is_valid_single_word(w): continue
                w_l = w.lower()
                existing = cefrj.get(w_l)
                if existing is None or CEFR_ORDER.get(level,99) < CEFR_ORDER.get(existing[0],99):
                    cefrj[w_l] = (level, pos)
    print(f"CEFR-J words loaded: {len(cefrj)}")

    # ---- Collect candidates ----
    # word_lower → {cefr_level, pos, tags[]}
    candidates: dict[str, dict] = {}

    def add_candidate(word: str, tags: list[str], cefr: str = "", pos: str = "") -> None:
        w_l = word.lower()
        if not _is_valid_single_word(w_l) or w_l in db_forms:
            return
        if w_l not in candidates:
            candidates[w_l] = {"word": word, "cefr": cefr, "pos": pos, "tags": set()}
        c = candidates[w_l]
        c["tags"].update(tags)
        if cefr and (not c["cefr"] or CEFR_ORDER.get(cefr,99) < CEFR_ORDER.get(c["cefr"],99)):
            c["cefr"] = cefr
        if pos and not c["pos"]:
            c["pos"] = pos

    # YLE lists (all levels — these are critical curriculum words)
    for w in YLE_STARTERS:
        cefr, pos = cefrj.get(w, ("A1", ""))
        add_candidate(w, ["source:cambridge_yle_starters", "source:cambridge_yle_movers",
                          "source:cambridge_yle_flyers"], cefr=cefr, pos=pos)
    for w in YLE_MOVERS:
        cefr, pos = cefrj.get(w, ("A2", ""))
        add_candidate(w, ["source:cambridge_yle_movers", "source:cambridge_yle_flyers"],
                      cefr=cefr, pos=pos)
    for w in YLE_FLYERS:
        cefr, pos = cefrj.get(w, ("A2", ""))
        add_candidate(w, ["source:cambridge_yle_flyers"], cefr=cefr, pos=pos)

    # UK statutory lists
    for w in UK_Y1_Y2:
        cefr, pos = cefrj.get(w.lower(), ("A1", ""))
        add_candidate(w, ["source:uk_y1_y2"], cefr=cefr, pos=pos)
    for w in UK_Y3_Y4:
        cefr, pos = cefrj.get(w.lower(), ("A2", ""))
        add_candidate(w, ["source:uk_y3_y4"], cefr=cefr, pos=pos)

    # CEFR-J up to max level
    for w_l, (level, pos) in cefrj.items():
        if CEFR_ORDER.get(level, 99) <= max_level_order:
            add_candidate(w_l, [], cefr=level, pos=pos)

    print(f"Candidates to insert: {len(candidates)}")
    if not candidates:
        print("Nothing to add — DB already complete for these sources.")
        con.close()
        return 0

    # Group by CEFR level
    from collections import Counter
    level_dist = Counter(c["cefr"] for c in candidates.values())
    for lvl in ["A1","A2","B1","B2","C1","C2"]:
        if level_dist[lvl]: print(f"  {lvl}: {level_dist[lvl]}")

    if args.dry_run:
        print("\nTop 20 candidates:")
        for w, c in sorted(candidates.items())[:20]:
            print(f"  {w:20s}  cefr={c['cefr']:3s}  pos={c['pos']:12s}  tags={sorted(c['tags'])}")
        print("(dry-run — no changes written)")
        con.close()
        return 0

    # ---- Insert ----
    inserted = 0
    for w_l in sorted(candidates):
        c = candidates[w_l]
        word = c["word"] if c["word"][0].isalpha() else w_l
        # Normalize UK/DE curriculum words to standard form
        word = word.strip()

        original_id = f"word_en_{next_id:05d}"
        next_id += 1

        word_type = _POS_MAP.get(c["pos"].lower(), "noun")  # default noun

        tags = sorted(c["tags"]) + ["source:curriculum_added"]
        meta = {
            "tags": tags,
            "cefr_level": c["cefr"] if c["cefr"] else None,
        }
        meta = {k: v for k, v in meta.items() if v is not None}

        enrichment = {
            "enrichment_status": "minimal",
            "primary_pos": c["pos"] or None,
            "primary_lemma": word,
            "definitions": [],
            "inflections": [],
            "pronunciation": [],
            "examples": [],
            "hyphenation": [],
            "expressions": [],
            "proverbs": [],
            "entryNotes": [],
            "hypernyms": [],
            "hyponyms": [],
            "holonyms": [],
            "meronyms": [],
            "coordinateTerms": [],
            "synonyms": [],
            "antonyms": [],
            "conceptnet": [],
            "wiktionary_translations": [],
            "wiktionary_derived_terms": [],
            "wiktionary_related_terms": [],
            "alternative_analyses": [],
            "wordnetSenses": [],
            "commonLearnerErrors": [],
            "spellingVariants": [],
            "inflectionData": [],
            "tags": tags,
            "sources": ["CURRICULUM"],
        }

        con.execute(
            "INSERT OR IGNORE INTO words "
            "(original_id, word, lemma, word_type, grade_level, "
            " enrichment_json, metadata_json) "
            "VALUES (?,?,?,?,?,?,?)",
            (
                original_id,
                word,
                word,
                word_type,
                1,
                json.dumps(enrichment, ensure_ascii=False),
                json.dumps(meta, ensure_ascii=False),
            ),
        )
        inserted += 1

    con.commit()
    con.close()

    print(f"\nInserted: {inserted} new entries")
    print(f"DB now has {7878 + inserted} entries (approx)")
    print("\nNext steps:")
    print("  python add_wordfreq_en.py --overwrite --no-compress")
    print("  python add_cefr_en.py --overwrite --no-compress")
    print("  python add_curriculum_en.py --overwrite --no-compress")
    print("  python add_uk_curriculum.py --overwrite --no-compress")
    print("  python add_llm_examples_en.py --grade --workers 3  (picks up new words)")

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
