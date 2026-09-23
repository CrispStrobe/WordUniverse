# The gold set

A sheet of generated items with a human verdict on each. It exists to answer
two questions that nothing else can:

- **How often are the games actually wrong?** The review models flag about one
  item in seven on their own, and roughly half of those turn out to be the
  model's error rather than the game's. Until somebody has labelled a sample
  by hand, every figure quoted about content quality is a comparison between
  runs rather than a rate.
- **Which model is worth listening to?** Two lanes currently flag at 13.3% and
  16.3%. That says nothing about which is right more often, and no amount of
  further reviewing will.

## Filling one in

Open `gold-set-<date>.txt`. Each item shows the prompt a learner sees, the
options, and which one the game keys as correct. On the `verdict:` line write
either

    verdict: ok

or the names of whatever is wrong, and a reason after a dash:

    verdict: keyed — Werkzeug is a tool, not the opposite of a toy
    verdict: appropriate, grammatical — a clinical sentence, and "convey" is
             not a word for year 4

The four names are `answerable`, `keyed`, `grammatical`, `appropriate` — the
same four the models are asked about, which is what makes the two comparable.

**A blank line means nobody got to that item.** It is not the same as passing
it and is not counted, so there is no harm in stopping half way; an hour on
the first eighty is worth more than a rushed pass over all of them.

Beside the sheet is `<sheet>.items.jsonl`, which says which item each number
is. Keep the two together — the scoring reads both.

## Scoring a filled sheet

    python3 tools/audit/review.py x \
      --score docs/review/gold-set-<date>.txt \
      --against /path/to/verdicts.jsonl

It prints, per model, precision — of what it flagged, how much you agreed was
wrong — and recall — of what you called wrong, how much it caught.

## What not to expect from it

It measures the *judges*, not the games. A model with 80% precision tells you
how much to trust its flags; it does not tell you the games are 80% right.
And a sheet is a sample: 155 items out of a space above a hundred thousand.

It is also worth saying that the person filling it in should not be the person
who wrote the rules. Every content rule in this repository was written against
examples I judged myself, so a sheet I label measures how consistent I am, not
whether I was right.


## What the first (provisional) reading found

`gold-set-2026-09-23.txt` is labelled, and `gold-set-2026-09-23.verdicts.jsonl`
holds two models' verdicts on the same 155 items, so the two can be compared.
The labels are the assistant's own, which is the limitation stated at the top
of that file — they measure how consistent one judgement is, not whether it
was right.

**30 of 142 items were called wrong (21%).** Against that:

| | precision | recall |
|---|---:|---:|
| either lane flagged it | 48.4% | 53.6% |
| both lanes agreed | 60.0% | 10.7% |

Two things follow, and the second was a surprise.

**Requiring two models to agree is a worse filter than it looked.** It buys
twelve points of precision and costs forty-three of recall: three of twenty-
eight real problems caught instead of fifteen. Earlier notes described
agreement as isolating "the part worth acting on", which overstated it —
agreement mostly discards true findings. It is defensible for ranking a short
list; it is not a way to find problems.

**The models are excellent at keying and poor at suitability**, and the
remaining defects are almost all suitability:

| | labelled wrong | a model caught it |
|---|---:|---:|
| keyed | 8 | 8 — all of them |
| appropriate | 22 | 8 |

Every wrong answer was caught. Two thirds of the age-appropriateness problems
were not — and those are 22 of the 30. So the review is worth running for
keying, and appropriateness is work for rules rather than for models. The
rules that came out of this reading were a wine sentence in the compound game
and "testicular" offered as a distractor; the larger pattern it exposed is
glosses written for adults being shown to seven-year-olds — a giraffe
explained with "ossicones" and "genus Giraffa", a chimney as a tube emitting
"environmentally polluting gaseous and solid matter", a sphere given its
mathematical definition. That is the next rule worth writing.
