#!/usr/bin/env python3
"""English synonyms by sense, from WordNet's sense order.

The EN pipeline (pipeline/voc-en/13_wordnet_expansion.py) took every
WordNet synset of a word, in every word class, put their lemmas in one set
and sorted it. So "know" and "love" listed "fuck" (sense 8, sleep
together), "make" listed "shit" (sense 29, defecate), "tools" listed
"cock, dick, prick" and "water" listed "piss"; 661 words listed themselves.

WordNet numbers a word's senses by how often each was tagged in SemCor, the
most frequent first. A term of sense 1 is a synonym of what a child means
by the word; a term of sense 29 is not. WordNet marks only some vulgar
senses (``obscenity``, ``ethnic_slur``, ``disparagement`` usage domains:
"cock" is marked, "shit" and "piss" are not), so a short list of vulgar
words is checked as well.

WordNet 3.0 (Princeton, WordNet licence), read through NLTK.
"""
import re

POS = {'noun': 'n', 'verb': 'v', 'adjective': 'as', 'adverb': 'r'}
OFFENSIVE_DOMAINS = {'obscenity.n.02', 'ethnic_slur.n.01', 'disparagement.n.01'}
# Whole words of a term; a term with one of these in it is not shown.
VULGAR = {'fuck', 'fucking', 'shit', 'shitty', 'piss', 'pissed', 'cock', 'dick',
          'prick', 'cunt', 'twat', 'pussy', 'whore', 'whorehouse', 'whoremaster',
          'whoremonger', 'slut', 'sluttish', 'arse', 'ass', 'asshole', 'arsehole',
          'bitch', 'bastard', 'wanker', 'retard', 'retarded', 'nigger', 'fag',
          'faggot', 'dyke', 'tits', 'boob', 'boobs', 'bugger', 'crap',
          'shag', 'bonk', 'jerk off', 'jack off', 'turd', 'testis',
          'testicle', 'penis', 'vagina', 'vulva', 'scrotum', 'genitals',
          'fornicate', 'copulate', 'intercourse', 'sodomize', 'masturbate'}

# How often three model judges accepted a term of the tier as a synonym of
# the word's usual meaning (2,787 English words, Nov 2026): 0: 40%, 1: 18%,
# 2: 7%, 3: 4%, 4: 5%. The vulgar list took out 90 judged terms, none
# accepted.
WEAK_TIERS = {2, 3, 4}   # dropped from the pack unless a review accepted the term
TIERS = {
    0: 'WordNet sense 1 of the word, in its class',
    1: 'WordNet senses 2-3, in its class',
    2: 'a later WordNet sense, in its class',
    3: 'WordNet, another word class',
    4: 'not in WordNet',
}


def _norm(term):
    return term.replace('_', ' ').strip().lower()


def vulgar(term):
    t = _norm(term)
    if t in VULGAR:
        return True
    words = re.findall(r"[a-z]+", t)
    return any(w in VULGAR for w in words) or any(
        f'{a} {b}' in VULGAR for a, b in zip(words, words[1:]))


class WordNet:
    def __init__(self):
        from nltk.corpus import wordnet as wn
        self.wn = wn
        self._offensive = None

    def offensive(self, term):
        """True if some synset holding the term is marked obscene or a slur."""
        if self._offensive is None:
            bad = set()
            for s in self.wn.all_synsets():
                if {d.name() for d in s.usage_domains()} & OFFENSIVE_DOMAINS:
                    bad.update(_norm(l.name()) for l in s.lemmas())
            self._offensive = bad
        return _norm(term) in self._offensive

    def sense_rank(self, word, word_type):
        """{lemma: (same class?, rank)} over the word's synsets."""
        pos = POS.get(word_type)
        out = {}
        for same in (True, False):
            for rank, s in enumerate(
                    [s for s in self.wn.synsets(word.replace(' ', '_'))
                     if (s.pos() in pos) == same] if pos else
                    (self.wn.synsets(word.replace(' ', '_')) if same else []), 1):
                for l in s.lemmas():
                    out.setdefault(_norm(l.name()), (same, rank))
        return out


def tier_of(placed):
    if placed is None:
        return 4
    same, rank = placed
    if not same:
        return 3
    return 0 if rank == 1 else 1 if rank <= 3 else 2


def review(word, word_type, listed, wordnet):
    """(drop, ranked) as in thesaurus_de.review, by WordNet sense order."""
    ranks = wordnet.sense_rank(word, word_type)
    drop, ranked, seen = {}, [], set()
    for term in listed:
        text = term.replace('_', ' ').strip()
        k = text.lower()
        if not text:
            continue
        if k == word.lower():
            drop[term] = 'self'
        elif vulgar(text) or wordnet.offensive(text):
            drop[term] = 'offensive'
        elif k in seen:
            drop[term] = 'duplicate'
        else:
            seen.add(k)
            ranked.append((tier_of(ranks.get(k)), len(ranked), text))
    ranked.sort()
    return drop, [(text, tier) for tier, _, text in ranked]


def clean_antonyms(word, listed, wordnet):
    out, drop, seen = [], {}, set()
    for term in listed:
        text = term.replace('_', ' ').strip()
        k = text.lower()
        if not text:
            continue
        if k == word.lower():
            drop[term] = 'self'
        elif vulgar(text) or wordnet.offensive(text):
            drop[term] = 'offensive'
        elif k in seen:
            drop[term] = 'duplicate'
        else:
            seen.add(k)
            out.append(text)
    return drop, out
