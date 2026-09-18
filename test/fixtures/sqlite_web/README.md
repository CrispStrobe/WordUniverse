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

CI runs exactly this (see .github/workflows/ci.yml); it gates the deploy,
because the web storage and install path is what the deployed build runs.

When updating the SQLite dependencies, regenerate the app binaries using the
resolved repository dependencies, then rerun the browser tests:

```
dart run sqflite_common_ffi_web:setup --force
```

The verification fix used sqflite_common_ffi_web 1.1.1 and its setup-selected
sqlite3-3.1.2/sqlite3.wasm release. The old worker rejected `setWebOptions`.
Checkouts must preserve symlinks (particularly on Windows, and on network
mounts that store a symlink as a regular file containing its target path).

The symptom when they are not preserved: the server answers 200 with a ~25-byte
body, the wasm never instantiates, and every browser test hangs until its
30-second timeout — including tests that have nothing to do with SQLite. Check
with `git ls-files -s` (mode 120000) against what is actually on disk. To run
the suite on such a filesystem, copy `web/sqlite3.wasm` and `web/sqflite_sw.js`
over the two entries, run, then `git checkout -- test/fixtures/sqlite_web/`.

Do not replace these with separate test-only binaries, mocks, or an in-memory
database.
