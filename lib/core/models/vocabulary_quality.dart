import 'vocabulary_models.dart';
import 'word_features.dart';

/// Returns whether [entry] is safe to present as a vocabulary headword.
///
/// The source databases contain a small number of learner-error records whose
/// definitions explicitly describe them as misspellings. They are useful as
/// distractors, but must never become prompts or catalogue entries.
///
/// For an un-hydrated word the definition check is skipped: it was already
/// applied — over the same markers, in SQL — when the pack's feature index was
/// built, which is what lets the catalogue load without decoding enrichment.
/// See db_feature_index.dart.
bool isPresentableVocabularyEntry(GermanWord entry) {
  if (!_cleanHeadword.hasMatch(entry.word.trim())) return false;
  if (!wordSuitsAChild(entry.word)) return false;
  if (entry.sources.any(_isMisspellingSource)) return false;
  if (!entry.isHydrated) return true;

  final enrichment = entry.apiEnrichment;
  if (enrichment == null) return true;
  final description = [
    ...enrichment.definitions,
    ...enrichment.entryNotes,
  ].join(' ').toLowerCase();
  return !_invalidSpellingMarkers.any(description.contains);
}

final RegExp _cleanHeadword = RegExp(
  r"^[A-Za-zÀ-ÖØ-öø-ÿẞ]+(?:[-'’][A-Za-zÀ-ÖØ-öø-ÿẞ]+)*$",
);

bool _isMisspellingSource(String source) {
  final normalized = source.toUpperCase();
  return normalized.contains('COMMON_MISSPELLED') ||
      normalized.contains('COMMON_MISSPELLING');
}

const _invalidSpellingMarkers = <String>[
  'misspelling of',
  'misspelt form of',
  'misspelled form of',
  'incorrect spelling of',
  'nonstandard spelling of',
  'obsolete spelling of',
  'obsolete form of',
  'archaic form of',
  'archaic spelling of',
  'falschschreibung von',
];

/// Whether a gloss describes a name or a place rather than a meaning.
///
/// Wiktionary writes proper nouns with a fixed set of openings, and the packs
/// do not always type them as proper nouns: "franklin" arrives as an ordinary
/// grade-3 word glossed "A surname transferred from the nickname", and
/// "columbia" as "America; the United States; an appellation given in honor of
/// Christopher Columbus". Neither is vocabulary a learner can reason about.
bool describesAName(String definition) {
  final lower = definition.toLowerCase();
  // A capital and a city in one gloss is a place, however the sentence is
  // put together: "The capital and largest city of Germany" matched none of
  // the phrases below, and berlin reached an English definition quiz.
  if (lower.contains('capital') && lower.contains('city')) return true;
  if (_geographyGloss.hasMatch(lower)) return true;
  return kNameGlossOpenings.any(lower.startsWith) ||
      kNameGlossPhrases.any(lower.contains);
}

/// The German pack's way of glossing a place: the kind of place, then where
/// it is. "Stadt im US-Bundesstaat Pennsylvania", "Staat in Ostasien",
/// "Bundesstaat im Südosten der USA", "Kontinent, der das Festland des
/// Staats Australien … umfasst" — 78 entries, of which 66 were still typed
/// as ordinary nouns, so Australien, China, Texas, Leipzig and Sydney were
/// vocabulary. "Australien" reached the word of the day.
///
/// The locating word right after the noun is what makes this safe: without
/// it the same nouns open the glosses of the ordinary words they are —
/// "Ausland: Land oder Länder außerhalb des eigenen Staatsgebiets", "Insel:
/// vollständig von Wasser umgebenes Stück Land", "Fluss: größeres,
/// fließendes Gewässer". None of those matches.
final RegExp _geographyGloss =
    RegExp(r'^(hauptstadt|stadt|fluss|insel|gebirge|ozean|provinz|bundesland'
        r'|bundesstaat|kontinent|staat|region|gemeinde|dorf)\s*,?\s*'
        r'(in|im|der|des|von|vom|zwischen|an|auf|nahe|bei|südlich|nördlich'
        r'|östlich|westlich|mit)\b');

/// Gloss openings Wiktionary uses for names. Also compiled into SQL when the
/// feature index is built, so a light word can answer the same question.
const List<String> kNameGlossOpenings = [
  'a surname',
  'a male given name',
  'a female given name',
  'a given name',
  'a unisex given name',
  'a placename',
  'a place name',
  'an appellation',
  'a diminutive of the male',
  'a diminutive of the female',
  // Three entries in the English pack word it differently and arrived as
  // ordinary vocabulary: "eddie" (A diminutive of Edward, Edgar, Edwin),
  // "fred" (A short version of Frederick, Alfred, or Wilfred) and "kirby"
  // (An English placename.). The pack now types all three proper_noun, so
  // the games never reach them; this list is what tells it to.
  'a diminutive of',
  'a short version of',
  'a short form of',
  'a shortened form of',
  'a nickname for',
  'an english placename',
];

/// Gloss phrases that name a place or person wherever they appear.
///
/// Deliberately not anchored to the start: Wiktionary writes "A
/// transcontinental country in the Caucasus" for Georgia, so a leading "a
/// country in" misses it. "Official name:" and "Capital:" are that style's
/// own markers and are the most reliable of these.
const List<String> kNameGlossPhrases = [
  'official name:', 'capital:',
  ' country in ', ' country of ', ' city in ', ' town in ', ' village in ',
  ' county in ', ' river in ', ' lake in ', ' province of ',
  // " state of " alone read "The state of being free from illness" as a
  // place, and took health, life and on out of the games.
  ' state of the united states',
  'an unincorporated community', 'a census-designated place',
  // Peoples, languages and the sky: "dravidian", "guatemalan", "franciscan"
  // and "fomalhaut" all arrive lowercase and untyped, and were being asked
  // as if they were vocabulary.
  'aboriginal peoples', 'ethnic group', 'a people of', 'a people in',
  'surname', 'in the solar system', 'county seat',
  'inhabitant of', 'native or inhabitant', 'in the constellation',
  'a family of related ethnicities',
  // Without the leading article: London is glossed "The capital city of the
  // United Kingdom", which "a capital city" missed.
  'capital city', 'capital of',
  // The German pack's grade glosses are written as sentences: "Afrika ist ein
  // Kontinent.", "Berlin ist eine Stadt."
  'ist ein kontinent', 'ist eine stadt', 'ist ein land', 'ist ein fluss',
  // And the appositive form the pack also uses: "eine Stadt in Nordrhein-
  // Westfalen, Deutschland" for Lünen.
  'eine stadt in', 'eine gemeinde in', 'ein ort in', 'ein fluss in',
  'ein stadtteil', 'ein bundesland', 'ein dorf in',
  'ist ein meer', 'ist ein gebirge', 'hauptstadt von',
  // Geography needs a naming context, not just the noun: "a person who lives
  // on an island" is not a place, "a large landmass smaller than a continent"
  // is not a continent, and "any disturbed state of the atmosphere" is not a
  // state of the union.
  ' island in ', ' island of ', ' archipelago in ', ' peninsula in ',
  ' continent in ', ' sea in ', 'an ocean', ' mountain range in ',
  'a capital of', 'a capital city',
  // Figures rather than places: "Mother of the prophet Samuel in the Old
  // Testament" is a name, not vocabulary.
  'in the old testament', 'in the new testament', 'in greek mythology',
  'in roman mythology', 'in norse mythology',
  // Religious figures: "jesus" reached an English grade 3 definition quiz,
  // keyed against "batman" and "cam".
  'the messiah', 'son of god', 'in christianity', 'in islam', 'in judaism',
  'in the bible', 'in the quran', 'biblical figure', 'a prophet',
];

/// Whether the entry's own gloss says it is a name or a place.
///
/// Brands, surnames and placenames reach the catalogue untyped — "a sony",
/// "columbia", "atlantic", "pennsylvania" — so [GermanWord.isProperNoun] does
/// not catch them. A name is not a word whose meaning a learner can reason
/// about, as a prompt or as a distractor.
bool namesSomething(GermanWord word) {
  // A light word has no gloss to read; the feature index answered this for it
  // when the pack was indexed.
  if (!word.isHydrated) return word.has(WordFeature.nameLike);
  // The first sense only. Wiktionary gives "january" a given-name sense and
  // "of" an island one, so reading further down turns ordinary words into
  // names; the entries where the name sense comes second — "isaac" — are
  // marked in the pack instead, where the CEFR level and the word lists are
  // there to tell a month from a first name. See tools/pack/repair_pack.py.
  final definition = word.displayDefinitions.firstOrNull;
  return definition != null && describesAName(definition);
}

/// Whether a WordNet sense is about a name rather than about the word.
///
/// Three signals, each measured against the English pack's 32,534 senses.
///
/// Its own gloss says so — [describesAName] already reads those. Its
/// synonyms are capitalised while the headword is not, which is 4.1% of
/// senses and catches both "frost" carrying Robert Frost and "add" carrying
/// ADHD, "a kind of syndrome". Or it is scripture or myth: seventeen senses,
/// exactly the ones that made "job" a hero, "john" a Gospel and "james" an
/// Apostle.
///
/// The name sense is often the *first* one WordNet lists, so skipping it is
/// what stands between a child and "a frost is a kind of poet".
bool senseNamesSomething(WordNetSense sense,
    {required bool promptIsLowercase}) {
  final definition = sense.definition;
  if (definition != null) {
    if (describesAName(definition)) return true;
    if (_scriptureOrMyth.hasMatch(definition)) return true;
  }
  return promptIsLowercase && sense.synonyms.any(_startsCapitalised);
}

bool _startsCapitalised(String word) {
  if (word.isEmpty) return false;
  final first = word[0];
  return first != first.toLowerCase() && first == first.toUpperCase();
}

final RegExp _scriptureOrMyth = RegExp(
    r'\b(in the (old|new) testament|in (greek|roman|norse|egyptian) mythology'
    r'|in the bible|biblical|legendary|mythical)\b',
    caseSensitive: false);

/// Whether a phrasal verb is one to teach a child, judged by its meaning.
///
/// All 400 in the English pack were read. Two carry a meaning that is not for
/// a primary classroom, and only one of them matters: "lie by" is glossed "be
/// intimate with someone", which is a real archaic sense and therefore
/// nothing a correction could fix — the entry is accurate and should not be
/// taught. ("pass away — die or stop living" also matches and is kept: it is
/// the gentle expression a child is most likely to meet.)
///
/// A rule rather than a named exclusion because the list is somebody else's
/// and will grow. Deliberately narrow: "intimate" is barred in the phrasal
/// glosses only, where it means one thing, and not in ordinary sentences,
/// where an intimate friend is just a close one.
bool phrasalMeaningSuitsAChild(String meaning) => !_adultAct.hasMatch(meaning);

final RegExp _adultAct = RegExp(
    r'\b(be intimate|intimacy|sexual\w*|sleep with|make love|seduc\w*'
    r'|naked|aroused|fondle|molest\w*)\b',
    caseSensitive: false);

/// Whether a gloss is one a child can read, as opposed to one written for a
/// naturalist.
///
/// Labelling a gold set found the same fault in five games at once: a giraffe
/// explained as "A ruminant, of the genus Giraffa ... strictly speaking the
/// horn-like projections are ossicones", a chimney as "a tube used to emit
/// environmentally polluting gaseous and solid matter (including but not
/// limited to by-products of burning carbon- or hydrocarbon-based fuels)", a
/// dog as "A mammal of the family Canidae". They are shown as the hint beside
/// a word to find, trace or build, and as the card a memory pair matches.
///
/// Two signals, both measured. Length: over 180 characters is past the 95th
/// percentile in both packs and is not a hint any more. And the taxonomic
/// register — a rank followed by a Latin name, a Latin binomial, or the
/// hedges Wiktionary writes when it is being careful rather than clear.
/// Together they take 4.8% of English leading glosses and 1.9% of German.
///
/// What it does not catch is a gloss that is merely above the reader:
/// "honest" is explained with "scrupulous" and "swindling", which is out of
/// reach of a nine-year-old and of this rule. Telling those apart needs to
/// know which words the reader has, and the obvious way — count the gloss's
/// words that are not in the catalogue at the learner's grade — reads German
/// compounds and inflections as unknown and calls "Muttertier des Hausrinds"
/// the hardest gloss in the pack.
bool glossSuitsAChild(String gloss) =>
    gloss.trim().length <= _longestUsefulGloss &&
    !_taxonomicRegister.hasMatch(gloss);

/// Past the 95th percentile of leading glosses in both packs.
const int _longestUsefulGloss = 180;

final RegExp _taxonomicRegister =
    RegExp(r'\b(genus|species|subspecies|family|order|phylum|class)\s+[A-Z]'
        r'|\b[A-Z][a-z]+\s+[a-z]+ae\b'
        r'|\bstrictly speaking\b|\bso-called\b|\bincluding but not limited to\b'
        r'|\bder (Gattung|Familie|Ordnung)\b');

/// Whether a gloss describes a grammatical form rather than a meaning.
///
/// The packs carry inflected and derived entries whose "definition" is a
/// parse: "plural of passerby", "Partizip Präsens des Verbs wüten". Asked as
/// a question that is grammar homework at best, and at worst it keys a
/// misspelling — "simple past and past participle of annoint".
bool describesAGrammaticalForm(String definition) {
  final lower = definition.toLowerCase();
  return kGrammaticalFormMarkers.any(lower.contains);
}

/// Also compiled into SQL when the pack's feature index is built.
const kGrammaticalFormMarkers = <String>[
  // English
  'plural of', 'singular of', 'past participle of', 'present participle of',
  'simple past', 'third-person singular of', 'comparative of',
  'superlative of', 'inflection of', 'alternative form of',
  'alternative letter-case form of', 'gerund of',
  // German
  'des verbs', 'des substantivs', 'des adjektivs', 'partizip',
  'indikativ', 'konjunktiv', 'imperativ', 'person singular',
  'person plural', 'komparativ', 'superlativ', 'grundform',
  // Case names: "Nominativ Singular Femininum attributiv des
  // Indefinitpronomens jeder" is a parse, not a meaning.
  'nominativ', 'genitiv', 'dativ', 'akkusativ',
  'des pronomens', 'des indefinitpronomens', 'des artikels',
];

/// Whether a gloss says the entry is an abbreviation: "Abbreviation of July."
bool describesAnAbbreviation(String definition) {
  final lower = definition.toLowerCase();
  return kAbbreviationMarkers.any(lower.contains);
}

/// Also compiled into SQL when the pack's feature index is built.
const kAbbreviationMarkers = <String>[
  'abbreviation of',
  'initialism of',
  'acronym of',
  'short for',
  'abkürzung für',
  'kurzform von',
];

/// Whether a gloss can carry a question on its own.
///
/// A one-word gloss is a synonym, not an explanation — and when the pack is
/// wrong it is a misspelling pointing at another misspelling ("residental" is
/// glossed "residentiary"). A gloss ending in a colon is a domain label whose
/// text never arrived: the German pack offers "Botanik:" as the meaning of
/// "Mais".
bool isUsableDefinition(String definition) {
  final trimmed = definition.trim();
  if (trimmed.length < 4) return false;
  if (trimmed.endsWith(':')) return false;
  if (!trimmed.contains(' ')) return false;
  if (describesAGrammaticalForm(trimmed)) return false;
  if (describesAnAbbreviation(trimmed)) return false;
  if (describesAName(trimmed)) return false;
  if (_endsMidSentence(trimmed)) return false;
  return true;
}

/// Whether an example sentence is a whole sentence.
///
/// The packs' graded examples are generated two per grade, and the second one
/// is regularly cut off: "The process of pear cultivation involves", "Pears
/// are sweet". A gap exercise built on the first of those asks a child to
/// complete a sentence that was never finished. Eighty-eight per cent of the
/// English examples and ninety-nine per cent of the German ones end in a full
/// stop, and nine in ten words keep at least one, so this costs the games
/// little.
bool looksLikeAWholeSentence(String sentence) =>
    _endsInPunctuation.hasMatch(sentence.trim());

final RegExp _endsInPunctuation = RegExp(r'''[.!?][)"”'’]?$''');

/// Whether the gloss stops in the middle of itself — the German pack cuts
/// "eine Hupe am Kraftfahrzeug betätigen, um" off after the conjunction.
bool _endsMidSentence(String definition) {
  final trimmed = definition.trim();
  // "Eine Alternative ist,." — the generator stopped and punctuated anyway.
  if (trimmed.contains(',.') || trimmed.contains(' .')) return true;
  if (trimmed.endsWith(',') || trimmed.endsWith(';')) return true;
  // A gloss that ends in a full stop finished, whatever its last word is:
  // English definitions strand prepositions — "Everything that one is
  // capable of." — and reading those as truncated took "all", "can" and "by"
  // out of the games.
  if (RegExp(r'[.!?]$').hasMatch(trimmed)) return false;
  final stripped = trimmed.replaceAll(RegExp(r'[\s.,;:!?]+$'), '');
  if (stripped.isEmpty) return true;
  return _danglingWords
      .contains(stripped.split(RegExp(r'\s+')).last.toLowerCase());
}

const _danglingWords = <String>{
  // German
  'um', 'und', 'oder', 'dass', 'zu', 'mit', 'von', 'für', 'der', 'die', 'das',
  'ein', 'eine', 'einen', 'einem', 'einer', 'im', 'am', 'beim', 'zum', 'zur',
  'wenn', 'weil', 'sich', 'als', 'aus', 'auf', 'in',
  // English
  'to', 'of', 'the', 'a', 'an', 'and', 'or', 'that', 'with', 'for', 'by',
  'from', 'as', 'at', 'on',
};

/// Whether an example sentence is one to put in front of a nine-year-old.
///
/// The packs draw their examples from Wikipedia, news and Gutenberg, so a
/// perfectly ordinary word arrives with a perfectly unsuitable sentence: the
/// German pack illustrates "auffordern" with "Die syrische Armee fordert
/// Rebellen und Bewohner auf, die Stadt zu verlassen." A model reading the
/// generated items flagged that one; this is the rule that keeps it out.
///
/// A stopgap, and a deliberately short one — the packs mark nothing about
/// register or subject, so this is a word list, with all a word list's
/// limits. It filters sentences, never words: a game with no suitable
/// example shows none rather than showing that one. German nouns are matched
/// case-sensitively, which is what separates "Kriege" from "kriege".
bool sentenceSuitsAChild(String sentence) =>
    !_unsuitableGerman.hasMatch(sentence) &&
    !_unsuitableGermanAnyCase.hasMatch(sentence) &&
    !_unsuitableEnglish.hasMatch(sentence) &&
    !_adultSetting.hasMatch(sentence) &&
    !_archaicWords.hasMatch(sentence) &&
    !_archaicSpelling.hasMatch(sentence) &&
    !_clinicalAnatomy.hasMatch(sentence);

/// Reproductive anatomy, in the register a textbook uses.
///
/// Labelling a review sheet turned up a gap exercise asking a ten-year-old to
/// complete "The Fallopian Tubes, or oviducts, ___ the ova from the ovaries
/// to the cavity of the uterus." Nothing in it is a banned word — it is a
/// clinical sentence about a perfectly ordinary verb, "convey" — which is
/// why every rule above let it through.
///
/// Forty-five English sentences and ten German ones match, a quarter of one
/// per cent and a twenty-fifth of one, so nothing is lost by skipping them.
///
/// Words that are ordinary in another sense are left out on purpose: German
/// Samen is also seeds and Scheide a sheath or a scabbard, and English
/// "cervical" belongs to the neck as much as anywhere. A rule that took those
/// would cost more than it saves.
final RegExp _clinicalAnatomy = RegExp(
    r'\b(fallopian|oviducts?|ova|ovum|ovar(?:y|ies|ian)|uter(?:us|ine)'
    r'|vulva|vagina\w*|penis|penile|testis|testes|testicle\w*|scrotum'
    r'|semen|sperm\w*|ejaculat\w*|menstruat\w*|menses|cervix'
    r'|placenta\w*|womb|foreskin|genital\w*|gonad\w*|prostate'
    r'|copulat\w*|coitus|inseminat\w*|orgasm\w*'
    r'|Eierstock\w*|Eileiter\w*|Gebärmutter\w*|Eizelle\w*'
    r'|Spermium|Spermien|Samenzelle\w*|Hoden\w*|Hodensack'
    r'|Schamlippen|Vorhaut|Menstruation\w*|Plazenta|Mutterkuchen'
    r'|Geschlechtsorgan\w*|Genitalien|Samenerguss|Ejakulation\w*'
    r'|Begattung\w*|Koitus)\b',
    caseSensitive: false);

/// Early Modern English and Fraktur-era German. The packs' example sentences
/// are quarried from public-domain books, so a cloze gap arrives built on
/// "He that feareth oblatration must not travel", on Shakespeare quartos
/// still spelt with a long s ("pleaſeth your Lordſhip") and on the King James
/// Bible. Six per cent of the English sentences and a tenth of a per cent of
/// the German ones read like this.
final RegExp _archaicWords = RegExp(
    r'\b(thou|thee|thy|thine|hath|doth|dost|saith|shalt|shouldst|wilt'
    r'|wouldst|unto|verily|whosoever|whomsoever|hither|thither|whence'
    r'|thence)\b',
    caseSensitive: false);

/// The long s, and "-eth" written lowercase. The long s alone settles most of
/// them, in either language. Case-sensitive on purpose: a case-insensitive
/// "-eth" reads Elisabeth, Sabeth and Lambeth as archaic.
final RegExp _archaicSpelling = RegExp(r'[ſ]|\b[a-zäöüß]{3,}eth\b');

/// Settings a school exercise does not put a nine-year-old in. A model reading
/// the English cloze items found one built on "a beer commercial … two aliens
/// order a pint in a rural pub": grammatical, on-topic, and not a sentence a
/// primary teacher hands out. The packs hold millions of sentences, so the
/// cost of skipping these is nil.
final RegExp _adultSetting = RegExp(
    r'\b(beer|beers|pint|pints|pub|pubs|ale|lager|whisky|whiskey|vodka|'
    r'brandy|liquor|cocktail|cocktails|booze|drunk|drunken|tipsy|cigarette|'
    r'cigarettes|cigar|cigars|tobacco|casino|casinos|gambling|betting|'
    // Wine was missing, and a gold-set reading found the compound game
    // serving it: "Zum Abendessen gibt es heute einen besonders guten Wein."
    // A quarter of one per cent of the sentences in each pack.
    r'wine|wines|champagne|prosecco|'
    r'Bier|Biere|Kneipe|Kneipen|Schnaps|Wodka|Whisky|Likör|Alkohol|'
    r'Wein|Weine|Weins|Weines|Rotwein|Weißwein|Sekt|Champagner|'
    r'betrunken|besoffen|Zigarette|Zigaretten|Zigarre|Zigarren|Tabak|'
    r'Kasino|Casino|Glücksspiel)\b',
    caseSensitive: false);

final RegExp _unsuitableGerman = RegExp(
    r'\b(Armee|Rebell|Rebellen|Krieg|Kriege|Krieges|Kriegs\w*|Soldat|Soldaten|'
    r'Mord|Mordes|Morde|Waffe|Waffen|Terror\w*|Bombe|Bomben|Drogen|Heroin|'
    r'Kokain|Opium|Leiche|Leichen|Selbstmord|Suizid|Nazi|Nazis|Hitler|'
    r'Holocaust|'
    r'Massaker|Folter\w*|Vergewaltigung\w*|Prostituierte\w*)\b');

final RegExp _unsuitableGermanAnyCase = RegExp(
    r'\b(getötet|ermordet|erschossen|vergewaltig\w*|gefoltert|sexuell\w*)\b',
    caseSensitive: false);

final RegExp _unsuitableEnglish = RegExp(
    r'\b(army|armies|rebel|rebels|war|wars|warfare|soldier|soldiers|killed|'
    r'murder|murders|murdered|weapon|weapons|terroris\w*|bomb|bombs|bombed|'
    r'raped|raping|drugs|heroin|cocaine|prostitut\w*|corpse|corpses|suicide|'
    r'nazi|nazis|hitler|holocaust|massacre|tortur\w*|sexual\w*)\b',
    caseSensitive: false);

/// Whether the pack contradicts itself about the word's class.
///
/// Every entry carries a word_type column and, in its enrichment, a
/// primary_pos. They agree for 98% of the English pack and 99.5% of the
/// German one, and where they do not the column is the one that is wrong:
/// "at", "between", "by", "from", "in", "he", "his", "each" and "four" are
/// all filed as nouns with primary_pos saying preposition, pronoun,
/// determiner or numeral, and the German exceptions are abbreviations —
/// CDU, FBI, GmbH, GPS, dpa. A model reading the items was asked to sort
/// "at" into a word class and told the answer was "noun".
///
/// A game that asks about the class has to skip these, since it has no way
/// to know which of the two the pack means. Games that merely use the class
/// to pick distractors can go on using it.
bool classIsContradicted(GermanWord word) {
  final stated = word.apiEnrichment?.primaryPos?.trim().toLowerCase();
  if (stated == null || stated.isEmpty) return false;
  final normalized = _posSynonyms[stated] ?? stated;
  final column = _posSynonyms[word.wordType.name] ?? word.wordType.name;
  return normalized != column;
}

/// Whether the word's class is settled well enough to be the question.
///
/// Three opinions where the pack has them: the `word_type` column, the
/// entry's own `primary_pos`, and the classes its WordNet senses fall under.
/// A word-class game asks which class a word is, so it may only ask where
/// they agree.
///
/// The senses add what the other two cannot see. "answer" is filed as a noun
/// and its primary_pos agrees, and WordNet gives it five noun senses and ten
/// verb ones — a learner answering Verb is not wrong. "annoyed" is filed as a
/// verb, primary_pos agrees, and every one of its senses is an adjective.
/// Both were keyed against the learner in a 155-item sheet.
///
/// Measured on the English pack: of 11,511 entries in a binned class, 4,240
/// are settled, 2,554 span more than one class, 567 name a single class that
/// is not the column's, and 4,150 carry no senses and so are judged by the
/// first two opinions alone.
bool classIsSettled(GermanWord word) {
  if (classIsContradicted(word)) return false;
  final classes = <String>{};
  for (final sense
      in word.apiEnrichment?.wordnetSenses ?? const <WordNetSense>[]) {
    final pos = sense.pos?.trim().toLowerCase();
    if (pos == null || pos.isEmpty) continue;
    classes.add(_posSynonyms[pos] ?? pos);
  }
  if (classes.isEmpty) return true; // nothing more to go on
  if (classes.length > 1) return false; // "answer" is noun and verb
  final column = _posSynonyms[word.wordType.name] ?? word.wordType.name;
  return classes.single == column; // "annoyed" is only an adjective
}

/// Spellings the two fields use for the same class, on both packs.
const _posSynonyms = <String, String>{
  'noun': 'noun',
  'substantiv': 'noun',
  'proper_noun': 'noun',
  'name': 'noun',
  'propn': 'noun',
  'verb': 'verb',
  'aux': 'verb',
  'adjective': 'adj',
  'adjektiv': 'adj',
  'adj': 'adj',
  'adverb': 'adv',
  'adv': 'adv',
  'pronoun': 'pron',
  'pronomen': 'pron',
  'pron': 'pron',
  'numeral': 'num',
  'numerale': 'num',
  'num': 'num',
  'preposition': 'prep',
  'praeposition': 'prep',
  'prep': 'prep',
  'conjunction': 'conj',
  'konjunktion': 'conj',
  'conj': 'conj',
  'article': 'det',
  'artikel': 'det',
  'det': 'det',
  'determiner': 'det',
  'interjection': 'intj',
  'interjektion': 'intj',
  'intj': 'intj',
  'particle': 'part',
  'partikel': 'part',
  'part': 'part',
  'abbreviation': 'abbrev',
  'abbrev': 'abbrev',
  'andere': 'other',
  'other': 'other',
};

/// Whether the word itself belongs in a game for a nine-year-old.
///
/// A model reading the generated items found "sexual" offered as a word to
/// find in a grid, trace, build from letters and match — at English grade 3,
/// from four different games. The packs mark nothing about register, so this
/// is a word list with all a word list's limits: short, explicit, and about
/// the words no school exercise reaches for rather than about propriety in
/// general. It gates the catalogue, so such a word is not a prompt, an
/// option, or a distractor anywhere.
bool wordSuitsAChild(String word) => !_unsuitableWords.hasMatch(word.trim());

final RegExp _unsuitableWords = RegExp(
    r'^(sex|sexes|sexual\w*|sexuality|erotic\w*|porn\w*|orgasm\w*|'
    r'masturbat\w*|condom|condoms|brothel|brothels|prostitute|prostitutes|'
    r'rape|raped|rapist|penis|vagina|vulva|testicle|testicles|testicular|'
    r'ejaculat\w*|'
    r'sexuell\w*|Sexualität|Erotik|Porno\w*|Orgasmus|Kondom|Kondome|Bordell|'
    r'Hure|Huren|Nutte|Nutten|ficken|Fotze|Penis|Vagina|'
    r'kacken|Kacke|furzen|Furz|pissen|Pisse|Scheiße|scheißen|Kotze|kotzen|'
    // A word game keys one of four options. A model found the German pack's
    // gloss "massenhafte, systematische Verfolgung, Deportation, Vertreibung
    // ... und Vernichtung europäischer Juden" asked as a review question with
    // "der Holocaust" as the answer and three ordinary nouns beside it. These
    // are already barred from the example sentences; a multiple-choice prompt
    // is no better a place for them.
    r'Holocaust|Holokaust|holocaust|Völkermord|Genozid|genocide|'
    // Plain profanity. The list above grew from a model finding "sexual"
    // offered as a word to trace and to build from letters; this half grew
    // from sense-linked hypernyms reaching "fuck" at English grade 2 and
    // answering "a kind of pair". Twenty-four such entries are in the English
    // catalogue and nineteen of them are attested by nothing at all — they
    // carry `source:hermit` and no word list, which is how they arrived.
    // Words that earn their place stay: "prick" is on the curriculum list and
    // means to pierce, "hell" and "damn" are CEFR-J and ordinary enough.
    // Not "dick": it is German for thick, a grade-3 adjective, and this list
    // is matched case-insensitively against both packs. The golden sample
    // caught it. The English noun of the same spelling stays in the
    // catalogue as a result — unattested, and the price of not breaking a
    // word a seven-year-old is taught.
    r'fuck\w*|cunt|cock|asshole|arsehole|arse|bollocks|bugger|'
    r'faggot|nigger|slut|whore|twat|wank\w*|shit\w*|turd|crap|crappy|'
    r'bitch|bastard)$',
    caseSensitive: false);
