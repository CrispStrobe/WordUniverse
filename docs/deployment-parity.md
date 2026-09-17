# Pages / Vercel deployment parity

Investigation: 2026-09-17, starting at local HEAD
`64eee29c70aa004177f01c87f233e67a506ea8a6` (main, four commits ahead of origin).
No production deployment was performed. These observations describe the existing
live sites, not this local commit.

## Evidence before changes

Cache-busted GETs on both hosts at approximately 19:46 UTC, repeated at 19:50 UTC,
returned 200 for the document, main.dart.js, flutter.js, flutter_bootstrap.js and
sqlite3.wasm. Both / and /index.html were checked. No abort was reproduced.

| Response | Pages | Vercel |
| --- | --- | --- |
| JS Content-Type | application/javascript; charset=utf-8 | same |
| SQLite Content-Type | application/wasm | same |
| Cache-Control (all sampled assets) | max-age=600 | public, max-age=0, must-revalidate |
| COOP / COEP | absent | absent |
| Access-Control-Allow-Origin | * | * |
| Accept-Ranges | bytes | bytes |
| SQLite size | 706316 bytes | same, byte-identical |
| main.dart.js size | 4420877 bytes | 4432547 bytes |
| flutter.js size | 9553 bytes | 12136 bytes |
| flutter_bootstrap.js size | 9975 bytes | 13093 bytes |
| Base href | /WordUniverse/ | / |
| Bootstrap compile target / renderer | dart2js / canvaskit | dart2js / canvaskit |
| Bootstrap engineRevision | 77e2e94772b6eb43759e34ed1ad7da4674e19cab | 06a2e2a110089dff50fe635cffd2a61e1b24fbcd |

The bootstrap build list on both sites contains a dart2js/CanvasKit entry and an
empty entry; neither advertises a dart2wasm/skwasm build. The Vercel bootstrap also
contains wasmHashes, which does NOT mean it selected skwasm. CanvasKit and SQLite
still use WASM even when the Dart application is compiled to JavaScript.

Reproduce (GET, not just HEAD; saves bodies and headers outside the repo):

```sh
mkdir -p /tmp/wu-deploy-parity
for host in pages vercel; do
  if [ "$host" = pages ]; then
    base=https://crispstrobe.github.io/WordUniverse/
  else
    base=https://wortuniversum.vercel.app/
  fi
  for asset in '' index.html main.dart.js flutter.js flutter_bootstrap.js sqlite3.wasm; do
    name=${asset:-root}
    curl -sS --max-time 90 -D - \
      -o "/tmp/wu-deploy-parity/$host-$name" \
      -w '\nstatus=%{http_code} bytes=%{size_download}\n' \
      "${base}${asset}?parity=$(date +%s)"
  done
done
python3 -c 'import pathlib,re; p=pathlib.Path("/tmp/wu-deploy-parity"); [(print(h), print(re.search(r"_flutter.buildConfig = .*", (p/f"{h}-flutter_bootstrap.js").read_text())[0])) for h in ["pages","vercel"]]; print("sqlite identical:", (p/"pages-sqlite3.wasm").read_bytes()==(p/"vercel-sqlite3.wasm").read_bytes())'
```

## Configuration findings and scoped alignment

- web/index.html only references flutter.js and the generated
  flutter_bootstrap.js; there is no custom bootstrap or renderer override. Left
  unchanged: the release build determines the available renderer.
- Pages pins Flutter 3.44.2 and builds --release with the repository base href.
  CI/Vercel previously used floating stable, consistent with the observed engine
  drift (the live source revision cannot be established from these headers).
  CI now uses 3.44.2 too.
- Root vercel.json previously built --wasm with COOP same-origin and COEP
  credentialless. README says native Git integration is disconnected: Actions is
  the production deployer. CI generated a separate minimal vercel.json without
  those headers. This explains why inspecting root config alone was misleading.
- Root Vercel config and the manual deploy.sh now use --release (CanvasKit), as
  Pages and CI already did. Obsolete isolation headers are removed from root
  config; adding headers to Pages is not supported. Lack of isolation does not
  by itself prove WASM failure: skwasm can run single-threaded.
- Vercel JS/WASM responses now explicitly request public, max-age=600, equivalent
  to Pages' ten-minute browser freshness. Existing correct native MIME handling
  is retained, not overridden. HTML remains revalidated on Vercel; Pages' fixed
  HTML caching and CDN-specific headers cannot be made identical in this repo.
  Non-fingerprinted assets are NOT marked immutable. This trades Vercel's prior
  immediate revalidation for Pages-equivalent freshness, not stronger freshness.
- tools/prepare-vercel.mjs derives prebuilt config from root config and disables
  server builds. CI and the manual script now retain its headers and existing
  SPA rewrites instead of discarding them. Missing asset paths can still receive
  the SPA HTML fallback; valid tested paths did not. Manual deploys still use the
  locally installed Flutter: use 3.44.2 for SDK parity. deploy.sh was NOT executed
  (it commits, pushes and deploys).

## Validation and limits

Baseline: flutter test --reporter expanded: 626 passed, 6 skipped;
flutter analyze --fatal-infos: no issues;
flutter test --platform chrome test/core/services/db_platform --reporter expanded:
45 passed. Expected negative schema diagnostics occurred without test failures.

TDD: node --test tools/deployment-config.test.mjs failed all three checks before
alignment, then passed all three. It covers renderer flags/SDK pins, base href,
cache rules and prebuilt config generation from an unrelated working directory.
CI runs this check; no extra npm packages are needed. bash -n deploy.sh and
git diff --check also passed. flutter build web --release --base-href
/WordUniverse/ succeeded with the locally installed Flutter 3.44.4 (not the
CI pin); generated bootstrap advertised only dart2js/CanvasKit, and base href was
correct. The build also reported existing flutter_tts JS-interop WASM dry-run
warnings; the JavaScript release build succeeded. A pinned CI build and actual
Vercel header application remain to be
verified after an explicitly authorized future deployment.

The one-off nightly WASM fetch abort remains UNRESOLVED. The observed live sites
already shared renderer selection and correct SQLite MIME/body, so there is no
evidence of a deterministic renderer or MIME failure. SDK and deployment-policy
drift are real and now reduced, but are only possible contributors. CanvasKit
may load engine WASM from Flutter's CDN; app-origin headers would not affect that
response. A canceled request during navigation/context shutdown or transient
transport failure is also possible. No trace identifying the aborted URL and
browser lifecycle was available in this investigation. After deployment, repeat
these probes and the existing strict nightly A-F matrix on both hosts; inspect
the exact failed WASM URL and timing before attributing root cause. Do not add
retries or suppress request/page errors to make the test pass.
