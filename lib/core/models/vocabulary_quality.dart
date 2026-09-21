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
  return kNameGlossOpenings.any(lower.startsWith) ||
      kNameGlossPhrases.any(lower.contains);
}

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
    !_adultSetting.hasMatch(sentence);

/// Settings a school exercise does not put a nine-year-old in. A model reading
/// the English cloze items found one built on "a beer commercial … two aliens
/// order a pint in a rural pub": grammatical, on-topic, and not a sentence a
/// primary teacher hands out. The packs hold millions of sentences, so the
/// cost of skipping these is nil.
final RegExp _adultSetting = RegExp(
    r'\b(beer|beers|pint|pints|pub|pubs|ale|lager|whisky|whiskey|vodka|'
    r'brandy|liquor|cocktail|cocktails|booze|drunk|drunken|tipsy|cigarette|'
    r'cigarettes|cigar|cigars|tobacco|casino|casinos|gambling|betting|'
    r'Bier|Biere|Kneipe|Kneipen|Schnaps|Wodka|Whisky|Likör|Alkohol|'
    r'betrunken|besoffen|Zigarette|Zigaretten|Zigarre|Zigarren|Tabak|'
    r'Kasino|Casino|Glücksspiel)\b',
    caseSensitive: false);

final RegExp _unsuitableGerman = RegExp(
    r'\b(Armee|Rebell|Rebellen|Krieg|Kriege|Krieges|Kriegs\w*|Soldat|Soldaten|'
    r'Mord|Mordes|Morde|Waffe|Waffen|Terror\w*|Bombe|Bomben|Drogen|Heroin|'
    r'Kokain|Leiche|Leichen|Selbstmord|Suizid|Nazi|Nazis|Hitler|Holocaust|'
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
    r'rape|raped|rapist|penis|vagina|vulva|testicle|testicles|ejaculat\w*|'
    r'sexuell\w*|Sexualität|Erotik|Porno\w*|Orgasmus|Kondom|Kondome|Bordell|'
    r'Hure|Huren|Nutte|Nutten|ficken|Fotze|Penis|Vagina|'
    r'kacken|Kacke|furzen|Furz|pissen|Pisse|Scheiße|scheißen|Kotze|kotzen)$',
    caseSensitive: false);
