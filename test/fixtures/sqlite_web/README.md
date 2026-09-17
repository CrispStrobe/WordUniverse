# Browser SQLite fixtures

Flutter's Chrome test server serves `test/` at the URL root, not the repository
root. The symlinks here expose the app's exact `web/sqlite3.wasm` and
`web/sqflite_sw.js` binaries under `/fixtures/sqlite_web/` without duplicate copies.
The schema suite uses the default worker-backed sqflite factory and real Chrome
IndexedDB; only the two resource URLs differ from the app.

Run from the repository root:

```
flutter test --platform chrome test/core/services/db_platform
```

When updating the SQLite dependencies, regenerate the app binaries using the
resolved repository dependencies, then rerun the browser tests:

```
dart run sqflite_common_ffi_web:setup --force
```

The verification fix used sqflite_common_ffi_web 1.1.1 and its setup-selected
sqlite3-3.1.2/sqlite3.wasm release. The old worker rejected `setWebOptions`.
Checkouts must preserve symlinks (particularly on Windows). Do not replace these
with separate test-only binaries, mocks, or an in-memory database.
