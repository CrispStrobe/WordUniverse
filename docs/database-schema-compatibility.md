# Dictionary schema compatibility

Readiness requires a real, nonempty SQLite `words` table with `id`,
`original_id`, `word`, `word_type`, and `grade_level`. These columns support
DictionaryDatabaseService's ID/grade/statistics queries and word parsing.
Other word fields have parser defaults; language-specific `phrasal_verbs` and
`false_friends` tables and the search index are not required for game launch.
This is a structural guard, not a full row-content or database integrity audit.

The shared validator is used by native and web installed probes and opens,
and by service initialization. Rejected handles close; probes report false,
feeding the existing missing-pack/reoffer gate. Init repairs invalid cached
copies instead of reporting ready. A failed replacement never reports ready.
Probes use independent connections so they cannot close a live game handle.

Decoded bundled and downloaded bytes are written to an `.installing` name
and checked as SQLite before promotion. Native promotion is a rename; web
uses a second write because its virtual filesystem has no rename API. Staging
is cleaned up and the final open is checked again. Web promotion is not atomic
and temporarily needs space for both copies; interrupted writes are refused by
the next probe. Existing gzip/size/checksum protections remain unchanged.

Schema compatibility is separate from content freshness. Existing bundled EN
uses PRAGMA user_version=0; compatible legacy packs are accepted by schema
introspection, without a new version-number contract or migration. A compatible
old vocabulary is still usable. Remote content revisions, refresh policy, and
a content updater are deliberately deferred from this slice.
