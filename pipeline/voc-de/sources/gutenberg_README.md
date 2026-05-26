---
language:
- de
license: other
license_name: public-domain
task_categories:
- text-generation
- fill-mask
pretty_name: German Children's Literature Sentences (Project Gutenberg)
tags:
- german
- deutsch
- children
- kinderbuch
- gutenberg
- sentences
- literacy
- reading-level
size_categories:
- 10K<n<100K
---

# German Children's Literature Sentences

Example sentences extracted from German-language children's and youth books
sourced from the [Project Gutenberg DE Kinderbuch shelf](https://www.gutenberg.org/ebooks/bookshelf/376),
all published before 1927 and in the public domain.

The shelf lists 80 books, of which 6 are LibriVox audio-only recordings without
plain text on Gutenberg. One additional book (19530, Svend Fleuron, d. 1966) was
omitted as still under German copyright. Audio-only books are replaced where
possible with equivalent text editions (77905 for Grimm; Mondfahrt and Max und
Moritz covered by text editions already in the list) — leaving **73 text books**
in this corpus.

Built as part of the [Grundwortschatz](https://github.com/CrispStrobe/voc)
German vocabulary learning project.

## Dataset Contents

| File | Description |
|---|---|
| `data/sentences.parquet` | All extracted sentences with book metadata |

### Columns

| Column | Type | Description |
|---|---|---|
| `book_id` | int | Project Gutenberg ebook ID |
| `title` | string | Book title (from Gutenberg header) |
| `author` | string | Author name |
| `language` | string | Always `de` |
| `license` | string | Always `public domain` |
| `sentence` | string | Extracted sentence (5–25 words) |
| `word_count` | int | Number of whitespace-separated tokens |

## Books Included

All 80 books from the verified Gutenberg DE Kinderbuch shelf, paged through at
`/ebooks/bookshelf/376?start_index=0`, `26`, `51`, `76`.

| ID | Title | Author |
|---|---|---|
| [77905](https://www.gutenberg.org/ebooks/77905) | Deutsche Märchen (Grimms Märchen, 1921 ed.) | Jacob & Wilhelm Grimm |
| [19163](https://www.gutenberg.org/ebooks/19163) | Märchen für Kinder | H. C. Andersen |
| [23787](https://www.gutenberg.org/ebooks/23787) | Märchen-Sammlung | Ludwig Bechstein |
| [24571](https://www.gutenberg.org/ebooks/24571) | Der Struwwelpeter | Heinrich Hoffmann |
| [19791](https://www.gutenberg.org/ebooks/19791) | Der Struwwelpeter (alt. ed.) | Heinrich Hoffmann |
| [19792](https://www.gutenberg.org/ebooks/19792) | Der Struwwelpeter (alt. ed. 2) | Heinrich Hoffmann |
| [32034](https://www.gutenberg.org/ebooks/32034) | König Nußknacker und der arme Reinhold | Heinrich Hoffmann |
| [17161](https://www.gutenberg.org/ebooks/17161) | Max und Moritz | Wilhelm Busch |
| [19636](https://www.gutenberg.org/ebooks/19636) | Bildergeschichten | Wilhelm Busch |
| [2322](https://www.gutenberg.org/ebooks/2322) | Hans Huckebein | Wilhelm Busch |
| [21021](https://www.gutenberg.org/ebooks/21021) | Die Biene Maja und ihre Abenteuer | Waldemar Bonsels |
| [27220](https://www.gutenberg.org/ebooks/27220) | Himmelsvolk | Waldemar Bonsels |
| [22570](https://www.gutenberg.org/ebooks/22570) | Wo Gritlis Kinder hingekommen sind | Johanna Spyri |
| [7500](https://www.gutenberg.org/ebooks/7500) | Heidis Lehr- und Wanderjahre | Johanna Spyri |
| [7512](https://www.gutenberg.org/ebooks/7512) | Heidi kann brauchen, was es gelernt hat | Johanna Spyri |
| [7511](https://www.gutenberg.org/ebooks/7511) | Heidis Lehr- und Wanderjahre (alt. ed.) | Johanna Spyri |
| [20780](https://www.gutenberg.org/ebooks/20780) | Heimatlos | Johanna Spyri |
| [9859](https://www.gutenberg.org/ebooks/9859) | Vom This, der doch etwas wird | Johanna Spyri |
| [9861](https://www.gutenberg.org/ebooks/9861) | Was die Großmutter gelehrt hat | Johanna Spyri |
| [9860](https://www.gutenberg.org/ebooks/9860) | Moni der Geißbub | Johanna Spyri |
| [7888](https://www.gutenberg.org/ebooks/7888) | Wie Wiselis Weg gefunden wird | Johanna Spyri |
| [31204](https://www.gutenberg.org/ebooks/31204) | Peterchens Mondfahrt: Ein Märchenspiel | Gerdt von Bassewitz |
| [22209](https://www.gutenberg.org/ebooks/22209) | Siegfried, der Held | Rudolf Herzog |
| [22413](https://www.gutenberg.org/ebooks/22413) | Alaeddin und die Wunderlampe | Curt Moreck |
| [14221](https://www.gutenberg.org/ebooks/14221) | Aladdin und die Wunderlampe | Ludwig Fulda |
| [25722](https://www.gutenberg.org/ebooks/25722) | Leben und Schicksale des Katers Rosaurus | Amalie Winter |
| [39619](https://www.gutenberg.org/ebooks/39619) | Trotzkopf als Grossmutter | Suze La Chapelle-Roobol |
| [31309](https://www.gutenberg.org/ebooks/31309) | Der Trotzkopf | Emmy von Rhoden |
| [19778](https://www.gutenberg.org/ebooks/19778) | Alice's Abenteuer im Wunderland | Lewis Carroll (tr. Antonie Zimmermann) |
| [30165](https://www.gutenberg.org/ebooks/30165) | Die Abenteuer Tom Sawyers | Mark Twain (German tr.) |
| [31459](https://www.gutenberg.org/ebooks/31459) | Onkel Tom's Hütte Bd. 1 | Harriet Beecher Stowe (German tr.) |
| [31114](https://www.gutenberg.org/ebooks/31114) | Wunderbare Reise des kleinen Nils Holgersson | Selma Lagerlöf (German tr.) |
| [19790](https://www.gutenberg.org/ebooks/19790) | Der Schimmelreiter | Theodor Storm |
| [19789](https://www.gutenberg.org/ebooks/19789) | Der kleine Häwelmann | Theodor Storm |
| [8917](https://www.gutenberg.org/ebooks/8917) | Von Kindern und Katzen | Theodor Storm |
| [8923](https://www.gutenberg.org/ebooks/8923) | Die Regentrude | Theodor Storm |
| [8915](https://www.gutenberg.org/ebooks/8915) | Hinzelmeier | Theodor Storm |
| [8919](https://www.gutenberg.org/ebooks/8919) | Pole Poppenspäler | Theodor Storm |
| [6341](https://www.gutenberg.org/ebooks/6341) | Nachtstücke | E. T. A. Hoffmann |
| [17362](https://www.gutenberg.org/ebooks/17362) | Der Goldene Topf | E. T. A. Hoffmann |
| [9200](https://www.gutenberg.org/ebooks/9200) | Klein Zaches, genannt Zinnober | E. T. A. Hoffmann |
| [6640](https://www.gutenberg.org/ebooks/6640) | Märchen-Almanach 1828 | Wilhelm Hauff |
| [6638](https://www.gutenberg.org/ebooks/6638) | Märchen-Almanach 1826 | Wilhelm Hauff |
| [6639](https://www.gutenberg.org/ebooks/6639) | Märchen-Almanach 1827 | Wilhelm Hauff |
| [13451](https://www.gutenberg.org/ebooks/13451) | Der Mann im Mond | Wilhelm Hauff |
| [22516](https://www.gutenberg.org/ebooks/22516) | Ehstnische Märchen. Zweite Hälfte | Friedrich Reinhold Kreutzwald |
| [21658](https://www.gutenberg.org/ebooks/21658) | Ehstnische Märchen | Friedrich Reinhold Kreutzwald |
| [38972](https://www.gutenberg.org/ebooks/38972) | Eskimomärchen | — |
| [23393](https://www.gutenberg.org/ebooks/23393) | Japanische Märchen | — |
| [27206](https://www.gutenberg.org/ebooks/27206) | Neugesammelte Volkssagen aus dem Lande Baden | — |
| [30084](https://www.gutenberg.org/ebooks/30084) | Norwegische Volksmährchen Bd. 2 | Asbjørnsen & Moe |
| [29796](https://www.gutenberg.org/ebooks/29796) | Norwegische Volksmährchen Bd. 1 | Asbjørnsen & Moe |
| [35794](https://www.gutenberg.org/ebooks/35794) | Märchen und Erzählungen für Anfänger | — |
| [31281](https://www.gutenberg.org/ebooks/31281) | 500 Rätsel und Rätselscherze | Joseph Frick |
| [19716](https://www.gutenberg.org/ebooks/19716) | Hundert neue Rätsel | Angela Döring |
| [9158](https://www.gutenberg.org/ebooks/9158) | Fabeln und Erzählungen | Gotthold Ephraim Lessing |
| [9375](https://www.gutenberg.org/ebooks/9375) | Ausgewählte Fabeln | Gotthold Ephraim Lessing |
| [4501](https://www.gutenberg.org/ebooks/4501) | Gockel, Hinkel und Gackeleia | Clemens Brentano |
| [2380](https://www.gutenberg.org/ebooks/2380) | Das Märchen von dem Myrtenfräulein | Clemens Brentano |
| [6724](https://www.gutenberg.org/ebooks/6724) | Kater Martinchen | Ernst Moritz Arndt |
| [6641](https://www.gutenberg.org/ebooks/6641) | Märchen und Sagen | Ernst Moritz Arndt |
| [37940](https://www.gutenberg.org/ebooks/37940) | Rübezahl | Rosalie Koch |
| [40327](https://www.gutenberg.org/ebooks/40327) | Rübezahl | Rudolf Reichhardt |
| [13732](https://www.gutenberg.org/ebooks/13732) | Das liebe Nest | Paula Dehmel |
| [25530](https://www.gutenberg.org/ebooks/25530) | Die Nymphe des Brunnens | Johann Karl August Musäus |
| [19733](https://www.gutenberg.org/ebooks/19733) | Das kleine Dummerle | Agnes Sapper |
| [19971](https://www.gutenberg.org/ebooks/19971) | Hansi | Ida Frohnmeyer |
| [37202](https://www.gutenberg.org/ebooks/37202) | Kasperle auf Burg Himmelhoch | Josephine Siebe |
| [36813](https://www.gutenberg.org/ebooks/36813) | Kasperle auf Reisen | Josephine Siebe |
| [24413](https://www.gutenberg.org/ebooks/24413) | Tante Toni und ihre Bande | Alberta von Brochowska |
| [28279](https://www.gutenberg.org/ebooks/28279) | Woher die Kindlein kommen | Hans Hoppeler |
| [8392](https://www.gutenberg.org/ebooks/8392) | Hin und Her: Ein Buch für die Kinder | Henry H. Fick |
| [31213](https://www.gutenberg.org/ebooks/31213) | Schlupps, der Handwerksbursch | Clara Berg |

## Files

| File | Description |
|---|---|
| `gutenberg_corpus.db` | Complete SQLite DB — `books` + `sentences` tables, fully queryable |
| `data/sentences.parquet` | Same data as Parquet for HF datasets / streaming |

## Quick Start

**SQLite (recommended — query any word instantly):**

```python
import urllib.request, sqlite3

urllib.request.urlretrieve(
    "https://huggingface.co/datasets/CrispStrobe/german-childrens-lit-sentences"
    "/resolve/main/gutenberg_corpus.db",
    "gutenberg_corpus.db",
)
con = sqlite3.connect("gutenberg_corpus.db")

# All sentences containing "Hund"
rows = con.execute(
    "SELECT b.title, s.sentence FROM sentences s "
    "JOIN books b USING (book_id) "
    "WHERE s.sentence LIKE ?",
    ("%Hund%",),
).fetchall()
```

**HF Datasets (Parquet / streaming):**

```python
from datasets import load_dataset
ds = load_dataset("CrispStrobe/german-childrens-lit-sentences", split="train")
```

## Sentence Extraction

Sentences were extracted with the following pipeline:

1. Gutenberg header/footer stripped (between `*** START ***` and `*** END ***` markers)
2. German sentence splitting (`.!?` followed by uppercase, with abbreviation protection)
3. Noise filtering — sentences excluded if they contain URLs, chapter headings,
   Roman numerals, `_` or `*` markup, editorial bracket notes, multi-digit numbers
4. Length filter: **5–25 words** (whitespace-tokenised)

## Intended Use

- **Vocabulary learning**: authentic in-context examples for German words
- **Reading-level research**: spans Grimm fairy tales to Karl May adventure prose
- **Language model fine-tuning**: clean German prose, pre-1927
- **NLP benchmarking**: natural sentence length and complexity variation

## License

All source texts are in the **public domain** worldwide (pre-1927 publications).
The sentence extraction code is MIT licensed.
See individual Gutenberg book pages for original publication details.

## Citation

```bibtex
@misc{gutenberg_de_kinderbuch_sentences_2026,
  title        = {German Children's Literature Sentences},
  year         = {2026},
  howpublished = {Hugging Face Datasets},
  note         = {Extracted from Project Gutenberg DE Kinderbuch shelf
                  (\url{https://www.gutenberg.org/ebooks/bookshelf/376})
                  using the voc pipeline (\url{https://github.com/CrispStrobe/voc})},
}
```
