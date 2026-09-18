# Web delivery: what first load costs, and what the caching rules mean

Measured on a `flutter build web --release` of 3.44, gzipped — what a first
visitor actually downloads before the app paints:

| | gz | share |
|---|---|---|
| `canvaskit/canvaskit.wasm` | 2.84 MB | 71% |
| `main.dart.js` | 1.24 MB | 31% |
| `flutter.js` + `flutter_bootstrap.js` + `index.html` | 8 KB | <1% |
| **total** | **~4.0 MB** | |

The English pack (`assets/assets/grundwortschatz_en.db.gz`, 19 MB) is **not**
part of that: it is fetched when the pack is first installed, behind the
install progress UI.

## Why the game screens are not deferred

`import ... deferred as` would split the games out of `main.dart.js`. Source-map
attribution over the release bundle says that is not worth the routing rewrite:

| slice of `main.dart.js` (raw) | |
|---|---|
| Flutter framework + packages | 1199 KB |
| unattributed / shared | 894 KB |
| **all 30+ game screens** | **219 KB** |
| rest of the app | 200 KB |
| generated l10n | 78 KB |

Deferring every game would move ~5% of the raw bundle — on the order of 1–2% of
the compressed first load — while making every game entry an async, failure-prone
route. The engine wasm is the cost here, and no amount of app-side splitting
touches it.

Re-measure with:

```sh
flutter build web --release --source-maps   # then attribute main.dart.js.map
```

## Cache-Control rules (vercel.json)

The build emits **unversioned filenames**: `main.dart.js` and `canvaskit/*` live
at the same URLs in every deployment.

- **Everything matching `*.js` / `*.wasm` keeps `public, max-age=600`.** This is
  deliberate and predates this note: it matches GitHub Pages, which serves a
  fixed ten-minute freshness and cannot be configured. See
  [deployment-parity.md](deployment-parity.md). It is tempting to mark the 7 MB
  CanvasKit immutable, but the engine and the compiled app must match — a
  long-cached CanvasKit served against a fresh `main.dart.js` is a broken app
  with no recovery path for the user. That only becomes safe once these files
  are emitted under content-hashed names.

- **`assets/assets/{fonts,images,sounds}/*` and the pack `*.db.gz` are new:
  `max-age=31536000, immutable`.** These are addressed by filename — a changed
  font or image ships under a new name — and a pack database is verified against
  a pinned digest before it is installed, so a stale copy cannot mismatch the
  running build. This is where the bytes are: the English pack alone is 19 MB,
  and under the old blanket rule a client re-fetched it after ten minutes.
  Pages cannot express this, so the two hosts differ here on purpose.

`tools/deployment-config.test.mjs` pins both halves of that policy.

### Route patterns are path-to-regexp, not regex

Vercel parses a rule's `source` with path-to-regexp, where a group in the path
must be a *capture* group. `/assets/assets/(?:fonts|images|sounds)/(.*)` is
valid JavaScript regex — `new RegExp` accepts it, so a test that only compiles
the pattern passes — but the deploy fails validation with "invalid `source`
pattern". Wrap the alternation in a capture group instead:
`/assets/assets/((?:fonts|images|sounds)/.*)`.

The test guards against a bare non-capturing group. To check a config against
Vercel's own validator:

```sh
npm i @vercel/routing-utils
node -e "const {getTransformedRoutes}=require('@vercel/routing-utils');
  console.log(getTransformedRoutes(require('./vercel.json')).error ?? 'valid')"
```
