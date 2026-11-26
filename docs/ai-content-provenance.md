# AI-assisted learning content

The German and English packs contain selected example sentences and definitions
generated or revised using AI. The app discloses this during language setup, in
pack download/settings, in the game header's information action, and for word
entries with recorded AI contribution evidence. A pack is a mixed corpus; the
notice does not call every word or every dictionary field AI-generated. Existing
source and license information remains in place. No human-review claim is added.

## New pack builds

`tools/pack/ai_provenance.py` supplies application-recorded provenance. Accepted
fields are stored under `metadata_json.ai_content` (or `phrasal_verbs.ai_content_json`):

* `schema: word_universe.ai_content.v1` and a map keyed by the affected field;
* `origin: ai_generated` or `ai_assisted_revision`, according to the operation;
* a SHA-256 digest of the field's canonical JSON value;
* the successful allowlisted public provider's identifier/host, requested model,
  response model if present, and observed response time, when actually available;
* `details_status: recorded`, `partial`, or `unrecorded`.

Custom/private/tenant hosts are replaced with generic configured/local endpoint
labels. Model values that look like paths or URLs are omitted, including when
replaying checkpoints. Credentials and complete endpoint URLs are never exported.

The DE/EN example generators carry successful response metadata with each worker
result and JSONL checkpoint. Failed fallback attempts, dry runs, and unchanged
check results do not become new content origins. The phrasal-verb generator keeps
the source meaning's provenance separate from generated examples and later
revisions. The correction pipeline records successful lane responses, and its
overlay attaches origin only when accepted prose is written. Deterministic
first-name examples are not automatically labeled as generated AI content.

`content_provenance` stores a pack manifest with counts for recorded AI fields,
legacy AI evidence, unrecorded origin, and stale field digests. Phrasal entries are
counted separately where the new column exists. Counts describe evidence, not
the unknowable proportion of every historical token written by AI. A field hash
helps detect later edits; it is not a signature or a tamper-proof claim.

## Historical packs and checkpoints

Legacy `LLM_GENERATED`/`gloss_source` markers support a general disclosure but do
not establish an exact provider, model, response time, or human review. A replay
retains only the details the checkpoint actually saved. Unrecorded origin means
unknown, not human-authored. Loading an old pack does not backfill invented data.

This change does not regenerate or publish the shipped databases, replace their
integrity pins, contact inference providers, or alter source licenses. New builds
need the normal pack build/review/release process before the richer field records
are present in distributed artifacts. The Flutter model retains these records
when copying entries and serializing their metadata.

This is readable disclosure and machine-readable provenance, not an invisible
text watermark, C2PA implementation, cryptographic attestation, or a claim that
metadata alone satisfies the EU AI Act.

## Validation

Run `python3 -m unittest discover -s tools/pack -p '*_test.py'` for mocked-provider,
worker/checkpoint, field/source preservation, and existing overlay guard checks.
Focused Flutter tests cover metadata persistence, legacy unknowns, visible EN/DE
notices, and generated versus revised item details. Tests use fixture content and
make no inference requests.
