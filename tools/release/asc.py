#!/usr/bin/env python3
"""App Store Connect from CI: read the state, then change it deliberately.

    tools/release/asc.py status
    tools/release/asc.py testflight --build 6 --internal
    tools/release/asc.py testflight --build 6 --external --submit-beta-review
    tools/release/asc.py appstore   --build 6 --version 1.4.2 --submit

Credentials come from the environment, the same three secrets ios-release.yml
already uses, so nothing new has to be stored:

    ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8   (the key's PEM text)
    ASC_APP_ID                                  (numeric app id)

Every subcommand but `status` changes something outside this repository, and the
ones that cannot be undone say so before they run. Submitting a build for
external beta review puts it in front of Apple's reviewers; submitting an App
Store version asks for the release itself. Neither is implied by `status`.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = 'https://api.appstoreconnect.apple.com'


def token():
    """A short-lived ES256 JWT, which is the only auth this API takes."""
    import jwt  # PyJWT
    key_id = os.environ['ASC_KEY_ID']
    issuer = os.environ['ASC_ISSUER_ID']
    private_key = os.environ['ASC_API_KEY_P8']
    now = int(time.time())
    return jwt.encode(
        {'iss': issuer, 'iat': now, 'exp': now + 19 * 60, 'aud': 'appstoreconnect-v1'},
        private_key,
        algorithm='ES256',
        headers={'kid': key_id, 'typ': 'JWT'},
    )


def call(method, path, body=None, optional=False, _token=[]):
    """One request. With optional=True a 404 returns None instead of ending
    the run: Apple moves relationships between resources between API versions,
    and a report that dies on the first one it cannot find reports nothing."""
    if not _token:
        _token.append(token())
    url = path if path.startswith('http') else f'{API}{path}'
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header('Authorization', f'Bearer {_token[0]}')
    if data:
        request.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors='replace')
        if optional and error.code == 404:
            return None
        raise SystemExit(f'{method} {url}\n  HTTP {error.code}\n  {detail}')


def paged(path):
    out = []
    while path:
        page = call('GET', path)
        out += page.get('data', [])
        path = (page.get('links') or {}).get('next')
    return out


def app_id():
    return os.environ['ASC_APP_ID']


# ── read ────────────────────────────────────────────────────────────────────
def cmd_status(args):
    app = call('GET', f'/v1/apps/{app_id()}')['data']
    a = app['attributes']
    print(f"app: {a.get('name')}  bundle {a.get('bundleId')}  sku {a.get('sku')}")

    print('\nbuilds (newest first):')
    page = call('GET', f'/v1/builds?filter[app]={app_id()}&limit=20'
                       '&sort=-version&include=preReleaseVersion')
    # The platform matters: iOS and macOS number their builds independently, so
    # "build 5" appears twice and means two different binaries.
    pre = {i['id']: i['attributes'] for i in page.get('included', [])
           if i['type'] == 'preReleaseVersions'}
    for build in page.get('data', [])[:12]:
        b = build['attributes']
        rel = ((build.get('relationships') or {}).get('preReleaseVersion')
               or {}).get('data') or {}
        info = pre.get(rel.get('id'), {})
        print(f"  {info.get('platform', '?'):7} {info.get('version', '?'):8} "
              f"build {b.get('version'):>4}  {b.get('processingState'):10} "
              f"expired={str(b.get('expired')):5} {b.get('uploadedDate')}")

    print('\nbeta groups:')
    for group in paged(f'/v1/apps/{app_id()}/betaGroups?limit=50'):
        g = group['attributes']
        kind = 'internal' if g.get('isInternalGroup') else 'EXTERNAL'
        print(f"  {kind:9} {g.get('name')!r}  id={group['id']}  "
              f"publicLink={g.get('publicLinkEnabled')}")

    print('\napp store versions:')
    for version in paged(f'/v1/apps/{app_id()}/appStoreVersions?limit=20'):
        v = version['attributes']
        print(f"  {v.get('versionString'):8} {v.get('appStoreState')}  "
              f"platform={v.get('platform')}  id={version['id']}")

    print('\nreview submissions:')
    for sub in paged(f'/v1/reviewSubmissions?filter[app]={app_id()}&limit=5'):
        s = sub['attributes']
        print(f"  {s.get('state')}  platform={s.get('platform')}  "
              f"submitted={s.get('submittedDate')}  id={sub['id']}")
    return 0


# ── metadata readiness ──────────────────────────────────────────────────────
# What Apple blocks a submission on. Read-only, and the point of it is to say
# "this is missing" here rather than have a submission rejected for it.

# Apple accepts one iPhone size and one iPad size as the source for the rest.
# 6.9"/6.7" covers iPhone; 13"/12.9" covers iPad, and is only needed when the
# app actually ships for iPad.
IPHONE_SETS = ('APP_IPHONE_69', 'APP_IPHONE_67', 'APP_IPHONE_65')
IPAD_SETS = ('APP_IPAD_PRO_3GEN_129', 'APP_IPAD_PRO_129', 'APP_IPAD_113',
             'APP_IPAD_109')


def _ok(flag):
    return 'ok  ' if flag else 'MISSING'


def cmd_metadata(args):
    problems = []
    app = call('GET', f'/v1/apps/{app_id()}')['data']
    a = app['attributes']
    print(f"app: {a.get('name')}  bundle {a.get('bundleId')}")
    rights = a.get('contentRightsDeclaration')
    print(f"  {_ok(rights)}  content rights declaration: {rights}")
    if not rights:
        problems.append('content rights declaration is unset')

    # ── app-level: name, subtitle, privacy policy, categories ───────────────
    infos = paged(f'/v1/apps/{app_id()}/appInfos?limit=10')
    for info in infos:
        state = info['attributes'].get('appStoreState')
        if state in ('READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION'):
            continue
        print(f"\napp info ({state}):")
        for rel, label in (('primaryCategory', 'primary category'),
                           ('secondaryCategory', 'secondary category')):
            got = call('GET', f"/v1/appInfos/{info['id']}/{rel}").get('data')
            name = (got or {}).get('id')
            print(f"  {_ok(name or rel == 'secondaryCategory')}  {label}: {name}")
            if not name and rel == 'primaryCategory':
                problems.append('primary category is unset')
        for loc in paged(f"/v1/appInfos/{info['id']}/appInfoLocalizations"
                         '?limit=50'):
            la = loc['attributes']
            locale = la.get('locale')
            for field in ('name', 'subtitle', 'privacyPolicyUrl'):
                value = la.get(field)
                required = field in ('name', 'privacyPolicyUrl')
                print(f"  {_ok(value or not required)}  {locale} {field}: "
                      f"{(value or '')[:58]}")
                if required and not value:
                    problems.append(f'{locale}: {field} is empty')

    # ── version-level: description, what's new, screenshots ─────────────────
    versions = [v for v in paged(f'/v1/apps/{app_id()}/appStoreVersions'
                                 '?limit=20')
                if v['attributes'].get('platform') == args.platform]
    editable = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
                'METADATA_REJECTED', 'INVALID_BINARY'}
    target = None
    if args.version:
        target = next((v for v in versions
                       if v['attributes'].get('versionString') == args.version),
                      None)
        if target is None:
            print(f"\nno version {args.version} exists yet; it would be created "
                  "on submit, inheriting the metadata above")
    if target is None:
        target = next((v for v in versions
                       if v['attributes'].get('appStoreState') in editable), None)
    if target is None and args.live:
        # Nothing editable, so read the version that is on sale instead: a new
        # version inherits its metadata, so this is what 1.4.2 would start from.
        target = next((v for v in versions if v['attributes'].get(
            'appStoreState') == 'READY_FOR_SALE'), None)
        if target:
            print(f"\nno editable {args.platform} version; reading the live "
                  f"{target['attributes'].get('versionString')} instead, which "
                  "is what a new one inherits from")
    if target is None:
        print(f'\nno editable {args.platform} version. Nothing to submit '
              'until one is created.')
        print(f"\n{len(problems)} problem(s): " + ('none' if not problems else ''))
        for p in problems:
            print(f'  - {p}')
        return 1 if problems else 0

    va = target['attributes']
    print(f"\nversion {va.get('versionString')} ({va.get('appStoreState')}):")
    print(f"  release type: {va.get('releaseType')}")
    build = call('GET', f"/v1/appStoreVersions/{target['id']}/build").get('data')
    print(f"  {_ok(build)}  build attached: "
          f"{(build or {}).get('attributes', {}).get('version')}")
    if not build:
        problems.append('no build attached to the version')

    for loc in paged(f"/v1/appStoreVersions/{target['id']}"
                     '/appStoreVersionLocalizations?limit=50'):
        la = loc['attributes']
        locale = la.get('locale')
        description = la.get('description') or ''
        whats_new = la.get('whatsNew') or ''
        keywords = la.get('keywords') or ''
        print(f"  {locale}:")
        print(f"    {_ok(description)}  description ({len(description)} chars)")
        if not description:
            problems.append(f'{locale}: description is empty')
        live = va.get('appStoreState') == 'READY_FOR_SALE'
        print(f"    {'n/a ' if live and not whats_new else _ok(whats_new)}  "
              f"what's new ({len(whats_new)} chars)"
              f"{'  — a released version carries none' if live else ''}")
        if not whats_new and not live:
            problems.append(f"{locale}: what's new is empty")
        print(f"    {'ok  ' if keywords else 'none'}  keywords: {keywords[:48]}")
        sets = paged(f"/v1/appStoreVersionLocalizations/{loc['id']}"
                     '/appScreenshotSets?limit=50')
        shots = {}
        for s in sets:
            kind = s['attributes'].get('screenshotDisplayType')
            got = paged(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"
                        '?limit=20')
            shots[kind] = len(got)
        iphone = sum(n for k, n in shots.items() if k in IPHONE_SETS)
        ipad = sum(n for k, n in shots.items() if k in IPAD_SETS)
        print(f"    {_ok(iphone)}  iPhone screenshots: {iphone}"
              f"   iPad: {ipad}   sets: {shots or 'none'}")
        if not iphone:
            problems.append(f'{locale}: no iPhone screenshots')

    # Apple moved this off appStoreVersions and onto appInfos; ask both, in
    # that order, because the old path 404s with "The relationship
    # 'ageRatingDeclaration' does not exist" rather than an empty answer.
    rating = None
    for path in (f"/v1/appInfos/{infos[0]['id']}/ageRatingDeclaration"
                 if infos else None,
                 f"/v1/appStoreVersions/{target['id']}/ageRatingDeclaration"):
        if not path:
            continue
        got = call('GET', path, optional=True)
        if got and got.get('data'):
            rating = got['data']
            break
    print(f"  {_ok(rating)}  age rating declaration present")
    if not rating:
        problems.append('age rating declaration is unset')

    got = call('GET', f"/v1/appStoreVersions/{target['id']}"
                      '/appStoreReviewDetail', optional=True)
    review = (got or {}).get('data')
    if review:
        r = review['attributes']
        need_demo = r.get('demoAccountRequired')
        print(f"  ok    review contact: {r.get('contactFirstName')} "
              f"{r.get('contactLastName')} <{r.get('contactEmail')}>")
        print(f"  ok    demo account required: {need_demo}")
        if not r.get('contactEmail'):
            problems.append('review contact email is empty')
    else:
        print('  MISSING  app store review detail (contact information)')
        problems.append('app store review detail is unset')

    print(f"\n{len(problems)} problem(s)" + (':' if problems else ''))
    for p in problems:
        print(f'  - {p}')
    return 1 if problems else 0

def cmd_beta(args):
    """What external TestFlight needs, which is not what the App Store needs.

    Apple gates external testing on its own three things, and a missing one
    fails the beta submission rather than the release: the app's beta review
    contact, a beta description and feedback email per locale, and "What to
    Test" on the build itself. Internal testing needs none of them.
    """
    problems = []
    detail = call('GET', f'/v1/apps/{app_id()}/betaAppReviewDetail',
                  optional=True)
    d = ((detail or {}).get('data') or {}).get('attributes') or {}
    if d:
        print(f"ok    beta review contact: {d.get('contactFirstName')} "
              f"{d.get('contactLastName')} <{d.get('contactEmail')}>")
        print(f"ok    demo account required: {d.get('demoAccountRequired')}")
        if not d.get('contactEmail'):
            problems.append('beta review contact email is empty')
        if d.get('demoAccountRequired') and not d.get('demoAccountName'):
            problems.append('a demo account is required but not given')
    else:
        print('MISSING  beta app review detail')
        problems.append('beta app review detail is unset')

    print('\nbeta app localizations:')
    locales = paged(f'/v1/apps/{app_id()}/betaAppLocalizations?limit=50')
    if not locales:
        print('  MISSING  none at all')
        problems.append('no beta app localizations')
    for loc in locales:
        la = loc['attributes']
        locale = la.get('locale')
        description = la.get('description') or ''
        feedback = la.get('feedbackEmail') or ''
        print(f"  {locale}: {_ok(description)} description "
              f"({len(description)} chars)   {_ok(feedback)} feedback email: "
              f"{feedback}")
        if not description:
            problems.append(f'{locale}: beta description is empty')
        if not feedback:
            problems.append(f'{locale}: beta feedback email is empty')

    if args.build:
        build = find_build(args.build, args.platform)
        print(f"\nbuild {args.build} — what to test:")
        notes = paged(f"/v1/builds/{build['id']}/betaBuildLocalizations"
                      '?limit=50')
        if not notes:
            print('  MISSING  none set')
            problems.append(f'build {args.build}: no "what to test" text')
        for note in notes:
            na = note['attributes']
            text = na.get('whatsNew') or ''
            print(f"  {na.get('locale')}: {_ok(text)} ({len(text)} chars)")
            if not text:
                problems.append(
                    f"build {args.build}: \"what to test\" empty for "
                    f"{na.get('locale')}")

    print(f"\n{len(problems)} problem(s)" + (':' if problems else ''))
    for p in problems:
        print(f'  - {p}')
    return 1 if problems else 0


# Relationship names a review submission item can carry. Apple returns the
# relationships only when they are asked for by name, which is why reading
# item['relationships'] off a plain listing shows nothing at all — including for
# a submission that demonstrably has an item.
_ITEM_RELATIONSHIPS = ('appStoreVersion', 'appCustomProductPageVersion',
                       'appStoreVersionExperiment', 'appEvent')


def _submission_items(submission_id):
    """What a submission is actually asking Apple to look at."""
    page = call('GET', f'/v1/reviewSubmissions/{submission_id}/items'
                       '?limit=20&include=' + ','.join(_ITEM_RELATIONSHIPS),
                optional=True) or {}
    included = {(i['type'], i['id']): i.get('attributes') or {}
                for i in page.get('included', [])}
    described = []
    for item in page.get('data', []):
        rels = item.get('relationships') or {}
        for name in _ITEM_RELATIONSHIPS:
            ref = (rels.get(name) or {}).get('data')
            if not ref:
                continue
            a = included.get((ref['type'], ref['id']))
            if a is None:
                got = call('GET', f"/v1/{ref['type']}/{ref['id']}",
                           optional=True)
                a = ((got or {}).get('data') or {}).get('attributes') or {}
            if name == 'appStoreVersion':
                described.append(f"version {a.get('versionString')} "
                                 f"({a.get('platform')}, "
                                 f"{a.get('appStoreState')})")
            else:
                described.append(f"{name} {ref['id']}")
    return described or ['(nothing attached)']


def cmd_submissions(args):
    """List review submissions, and try to cancel the ones never sent.

    A submission with no submittedDate was started and never sent. Four macOS
    ones had accumulated here, none from this repository — nothing in it creates
    a submission, so they came from the web interface.

    They cannot be removed. DELETE is forbidden on the resource, and
    canceled=true is refused with "Resource is not in cancellable state",
    because cancelling applies to a submission actually in review. The cancel
    path stays because a *sent* submission can be cancelled, which is a real
    need; for an unsent one it will report the refusal per submission.

    That four coexist is also evidence against the thing that made them look
    urgent: App Store Connect plainly allowed each to be created while the
    previous was open, so they are clutter rather than a block. The fix that
    matters is in cmd_appstore, which now reuses an empty one instead of adding
    a fifth.
    """
    submissions = paged(f'/v1/reviewSubmissions?filter[app]={app_id()}'
                        '&limit=50')
    stale = []
    for sub in submissions:
        a = sub['attributes']
        never_sent = not a.get('submittedDate')
        mark = 'NEVER SENT' if never_sent else 'sent'
        print(f"  {a.get('state'):20} {a.get('platform'):7} {mark:10} "
              f"{a.get('submittedDate') or '':24} {sub['id']}")
        for item in _submission_items(sub['id']):
            print(f"      {item}")
        if never_sent and (not args.platform
                           or a.get('platform') == args.platform):
            stale.append(sub)

    if not args.cancel_stale:
        print(f"\n{len(stale)} never sent"
              + (f" on {args.platform}" if args.platform else '')
              + '. Pass --cancel-stale to cancel them.')
        return 0

    if not stale:
        print('\nnothing to cancel.')
        return 0
    # Cancelled, not deleted. The API is explicit about it:
    #   The resource 'reviewSubmissions' does not allow 'DELETE'.
    #   Allowed operations are: CREATE, GET_COLLECTION, GET_INSTANCE, UPDATE
    # so the operation is an update setting canceled, which is what App Store
    # Connect itself does when you cancel a submission.
    failed = 0
    for sub in stale:
        a = sub['attributes']
        # Refuse anything that has been sent, whatever its state says.
        if a.get('submittedDate'):
            print(f"  refusing {sub['id']}: it was sent on "
                  f"{a.get('submittedDate')}")
            continue
        try:
            call('PATCH', f"/v1/reviewSubmissions/{sub['id']}",
                 {'data': {'type': 'reviewSubmissions', 'id': sub['id'],
                           'attributes': {'canceled': True}}})
            print(f"  cancelled {a.get('platform')} {sub['id']}")
        except SystemExit as error:
            # Keep going: one submission Apple will not let go of should not
            # hide whether the others were cleared.
            failed += 1
            print(f"  could not cancel {sub['id']}:")
            for line in str(error).splitlines():
                print(f"      {line}")
    return 1 if failed else 0


def find_build(number, platform=None):
    """The build with this number, on this platform.

    The platform is not optional in practice: iOS and macOS number builds
    independently, so "build 5" names two different binaries here, and a macOS
    release that filtered only by number would attach the iOS one.
    """
    page = call('GET', f'/v1/builds?filter[app]={app_id()}'
                       f'&filter[version]={number}&limit=10'
                       '&include=preReleaseVersion')
    pre = {i['id']: i['attributes'] for i in page.get('included', [])
           if i['type'] == 'preReleaseVersions'}
    builds = page.get('data', [])
    if platform:
        matching = []
        for build in builds:
            ref = ((build.get('relationships') or {})
                   .get('preReleaseVersion') or {}).get('data') or {}
            if pre.get(ref.get('id'), {}).get('platform') == platform:
                matching.append(build)
        builds = matching
    if not builds:
        raise SystemExit(
            f'no build {number}'
            + (f' on {platform}' if platform else '')
            + f' for app {app_id()}')
    return builds[0]


def wait_for_processing(number, minutes, platform=None):
    deadline = time.time() + minutes * 60
    while True:
        build = find_build(number, platform)
        state = build['attributes']['processingState']
        print(f'  build {number}: {state}')
        if state == 'VALID':
            return build
        if state in ('INVALID', 'FAILED'):
            raise SystemExit(f'build {number} is {state}; nothing to distribute')
        if time.time() > deadline:
            raise SystemExit(f'build {number} still {state} after {minutes} min')
        time.sleep(60)


# ── TestFlight ──────────────────────────────────────────────────────────────
def set_what_to_test(build_id, text):
    """The tester-facing note on the build. External testing is blocked without
    it; internal testing is not, which is why it goes unnoticed."""
    locales = paged(f'/v1/builds/{build_id}/betaBuildLocalizations?limit=50')
    if not locales:
        call('POST', '/v1/betaBuildLocalizations', {
            'data': {'type': 'betaBuildLocalizations',
                     'attributes': {'locale': 'en-US', 'whatsNew': text},
                     'relationships': {'build': {'data': {
                         'type': 'builds', 'id': build_id}}}}})
        print('  what to test: created for en-US')
        return
    for loc in locales:
        call('PATCH', f"/v1/betaBuildLocalizations/{loc['id']}",
             {'data': {'type': 'betaBuildLocalizations', 'id': loc['id'],
                       'attributes': {'whatsNew': text}}})
        print(f"  what to test: set for {loc['attributes'].get('locale')}")


def cmd_testflight(args):
    build = wait_for_processing(args.build, args.wait, args.platform)
    build_id = build['id']
    if args.what_to_test:
        set_what_to_test(build_id, args.what_to_test)
    groups = paged(f'/v1/apps/{app_id()}/betaGroups?limit=50')
    wanted = []
    for group in groups:
        internal = group['attributes'].get('isInternalGroup')
        if args.internal and internal:
            wanted.append(group)
        if args.external and not internal:
            wanted.append(group)
    if args.group:
        wanted = [g for g in groups if g['attributes'].get('name') in args.group]
    if not wanted:
        raise SystemExit('no matching beta group; run `status` to list them')

    for group in wanted:
        name = group['attributes'].get('name')
        print(f"adding build {args.build} to {name!r}")
        call('POST', f"/v1/betaGroups/{group['id']}/relationships/builds",
             {'data': [{'type': 'builds', 'id': build_id}]})

    if args.submit_beta_review:
        # External testers cannot see a build until Apple has passed it.
        print('submitting for beta app review')
        call('POST', '/v1/betaAppReviewSubmissions',
             {'data': {'type': 'betaAppReviewSubmissions',
                       'relationships': {'build': {'data': {
                           'type': 'builds', 'id': build_id}}}}})
    return 0


# ── App Store ───────────────────────────────────────────────────────────────
def cmd_appstore(args):
    build = wait_for_processing(args.build, args.wait, args.platform)
    versions = [v for v in paged(f'/v1/apps/{app_id()}/appStoreVersions'
                                 '?limit=20')
                if v['attributes'].get('platform') == args.platform]
    editable = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED',
                'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
    version = next((v for v in versions
                    if v['attributes'].get('versionString') == args.version), None)
    if version is None:
        print(f'creating version {args.version}')
        version = call('POST', '/v1/appStoreVersions', {
            'data': {'type': 'appStoreVersions',
                     'attributes': {'platform': args.platform,
                                    'versionString': args.version},
                     'relationships': {'app': {'data': {
                         'type': 'apps', 'id': app_id()}}}}})['data']
    elif version['attributes'].get('appStoreState') not in editable:
        raise SystemExit(
            f"version {args.version} is "
            f"{version['attributes'].get('appStoreState')} and cannot be edited")

    print(f"attaching build {args.build} to version {args.version}")
    call('PATCH', f"/v1/appStoreVersions/{version['id']}/relationships/build",
         {'data': {'type': 'builds', 'id': build['id']}})

    # Per locale, and that matters: the listing is en-US and de-DE, so one
    # text for all of them puts German on the English page or the reverse.
    # `--whats-new de-DE=…` targets one; a bare value applies to every locale,
    # which is only right for a single-locale app.
    texts = {}
    default = None
    for entry in args.whats_new or []:
        locale, _, text = entry.partition('=')
        if text and '-' in locale and len(locale) <= 8:
            texts[locale] = text
        else:
            default = entry
    if texts or default:
        localizations = paged(f"/v1/appStoreVersions/{version['id']}"
                              '/appStoreVersionLocalizations?limit=50')
        known = {l['attributes'].get('locale') for l in localizations}
        for locale in texts:
            if locale not in known:
                raise SystemExit(
                    f'no {locale} localization on this version; it has '
                    f'{sorted(known)}')
        for loc in localizations:
            locale = loc['attributes'].get('locale')
            text = texts.get(locale, default)
            if text is None:
                print(f"  what's new left alone for {locale}")
                continue
            call('PATCH', f"/v1/appStoreVersionLocalizations/{loc['id']}",
                 {'data': {'type': 'appStoreVersionLocalizations',
                           'id': loc['id'],
                           'attributes': {'whatsNew': text}}})
            print(f"  what's new set for {locale} ({len(text)} chars)")

    if not args.submit:
        print('\nnot submitted. Pass --submit to ask Apple to review it.')
        return 0

    # Reuse an open, empty submission for this platform before making another.
    # Four unsent macOS ones had accumulated here, and the API has no way to
    # remove them: DELETE is forbidden on the resource, and canceled=true is
    # refused with "Resource is not in cancellable state" because cancelling
    # applies to a submission actually in review. An empty one is a usable
    # container, so use it rather than leave a fifth behind.
    reusable = None
    for open_submission in paged(f'/v1/reviewSubmissions'
                                 f'?filter[app]={app_id()}&limit=50'):
        a = open_submission['attributes']
        if (a.get('platform') == args.platform
                and not a.get('submittedDate')
                and a.get('state') == 'READY_FOR_REVIEW'
                and _submission_items(open_submission['id'])
                == ['(nothing attached)']):
            reusable = open_submission
            break
    if reusable is not None:
        submission = reusable
        print(f"reusing the empty submission {submission['id']}")
    else:
        print('creating a review submission')
        submission = call('POST', '/v1/reviewSubmissions', {
            'data': {'type': 'reviewSubmissions',
                     'attributes': {'platform': args.platform},
                     'relationships': {'app': {'data': {
                         'type': 'apps', 'id': app_id()}}}}})['data']
    # Roll it back if anything after this fails. A created-but-unsent
    # submission is not harmless: App Store Connect allows one open submission
    # per platform, so an orphan blocks the next release for that platform with
    # an error that never mentions it. Four macOS ones had accumulated here.
    try:
        call('POST', '/v1/reviewSubmissionItems', {
            'data': {'type': 'reviewSubmissionItems',
                     'relationships': {
                         'reviewSubmission': {'data': {
                             'type': 'reviewSubmissions',
                             'id': submission['id']}},
                         'appStoreVersion': {'data': {
                             'type': 'appStoreVersions',
                             'id': version['id']}}}}})
        call('PATCH', f"/v1/reviewSubmissions/{submission['id']}",
             {'data': {'type': 'reviewSubmissions', 'id': submission['id'],
                       'attributes': {'submitted': True}}})
    except SystemExit:
        # Nothing to roll back to: the resource allows neither DELETE nor a
        # cancel from this state, so an orphan cannot be cleaned up after the
        # fact. Which is why the reuse above matters more than a rollback would.
        if reusable is None:
            print(f"left an empty submission behind: {submission['id']}. It "
                  'cannot be deleted or cancelled through the API; the next '
                  'run of this command will reuse it.')
        raise
    print(f"submitted for review: {submission['id']}")
    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)

    sub.add_parser('status', help='read the app, builds, groups and versions')

    md = sub.add_parser('metadata',
                        help='what Apple would block a submission on')
    md.add_argument('--version', help='which version to check; default is the '
                                      'editable one')
    md.add_argument('--platform', default='IOS', choices=['IOS', 'MAC_OS'])
    sm = sub.add_parser('submissions',
                        help='list review submissions; delete unsent ones')
    sm.add_argument('--platform', choices=['IOS', 'MAC_OS'],
                    help='only consider this platform')
    sm.add_argument('--cancel-stale', action='store_true',
                    help='cancel the submissions that were never sent')

    bt = sub.add_parser('beta',
                        help='what external TestFlight would block on')
    bt.add_argument('--build', help='also check "what to test" on this build')
    bt.add_argument('--platform', default='IOS', choices=['IOS', 'MAC_OS'],
                    help='iOS and macOS number builds independently, so the '
                         'number alone names two binaries')

    md.add_argument('--live', action='store_true',
                    help='when nothing is editable, read the version on sale, '
                         'which is what a new one inherits from')

    tf = sub.add_parser('testflight', help='distribute a build to testers')
    tf.add_argument('--build', required=True)
    tf.add_argument('--platform', default='IOS', choices=['IOS', 'MAC_OS'])
    tf.add_argument('--internal', action='store_true')
    tf.add_argument('--external', action='store_true')
    tf.add_argument('--group', action='append',
                    help='an exact group name; repeatable')
    tf.add_argument('--what-to-test',
                    help='the tester-facing note on the build; external '
                         'testing is blocked without one')
    tf.add_argument('--submit-beta-review', action='store_true',
                    help='required before external testers can install')
    tf.add_argument('--wait', type=int, default=45,
                    help='minutes to wait for Apple to finish processing')

    st = sub.add_parser('appstore', help='attach a build and optionally submit')
    st.add_argument('--build', required=True)
    st.add_argument('--version', required=True)
    st.add_argument('--platform', default='IOS', choices=['IOS', 'MAC_OS'])
    st.add_argument('--whats-new', action='append',
                    help='"locale=text" for one locale, repeatable; a bare '
                         'value applies to every locale')
    st.add_argument('--submit', action='store_true',
                    help='ask Apple to review it. This is not reversible '
                         'without a developer rejection.')
    st.add_argument('--wait', type=int, default=45)

    args = parser.parse_args()
    return {'status': cmd_status, 'metadata': cmd_metadata,
            'submissions': cmd_submissions,
            'beta': cmd_beta, 'testflight': cmd_testflight,
            'appstore': cmd_appstore}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
