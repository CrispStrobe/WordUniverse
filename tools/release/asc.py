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


def call(method, path, body=None, _token=[]):
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
    builds = paged(f'/v1/builds?filter[app]={app_id()}&limit=10'
                   '&sort=-version&include=preReleaseVersion')
    included = {}
    for build in builds[:10]:
        b = build['attributes']
        print(f"  build {b.get('version'):>4}  {b.get('processingState'):12} "
              f"expired={b.get('expired')}  uploaded {b.get('uploadedDate')}")
        included[b.get('version')] = build['id']

    print('\nbeta groups:')
    for group in paged(f'/v1/apps/{app_id()}/betaGroups?limit=50'):
        g = group['attributes']
        kind = 'internal' if g.get('isInternalGroup') else 'EXTERNAL'
        print(f"  {kind:9} {g.get('name')!r}  id={group['id']}  "
              f"publicLink={g.get('publicLinkEnabled')}")

    print('\napp store versions:')
    for version in paged(f'/v1/apps/{app_id()}/appStoreVersions?limit=10'):
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
    versions = paged(f'/v1/apps/{app_id()}/appStoreVersions?limit=10')
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
    if target is None:
        print('\nno editable version. Nothing to submit until one is created.')
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
        print(f"    {_ok(whats_new)}  what's new ({len(whats_new)} chars)")
        if not whats_new:
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

    rating = call('GET', f"/v1/appStoreVersions/{target['id']}"
                         '/ageRatingDeclaration').get('data')
    print(f"  {_ok(rating)}  age rating declaration present")
    if not rating:
        problems.append('age rating declaration is unset')

    review = call('GET', f"/v1/appStoreVersions/{target['id']}"
                         '/appStoreReviewDetail').get('data')
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

def find_build(number):
    builds = paged(f'/v1/builds?filter[app]={app_id()}'
                   f'&filter[version]={number}&limit=5')
    if not builds:
        raise SystemExit(f'no build {number} for app {app_id()}')
    return builds[0]


def wait_for_processing(number, minutes):
    deadline = time.time() + minutes * 60
    while True:
        build = find_build(number)
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
def cmd_testflight(args):
    build = wait_for_processing(args.build, args.wait)
    build_id = build['id']
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
    build = wait_for_processing(args.build, args.wait)
    versions = paged(f'/v1/apps/{app_id()}/appStoreVersions?limit=20')
    editable = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED',
                'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
    version = next((v for v in versions
                    if v['attributes'].get('versionString') == args.version), None)
    if version is None:
        print(f'creating version {args.version}')
        version = call('POST', '/v1/appStoreVersions', {
            'data': {'type': 'appStoreVersions',
                     'attributes': {'platform': 'IOS',
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

    if args.whats_new:
        for loc in paged(f"/v1/appStoreVersions/{version['id']}"
                         '/appStoreVersionLocalizations?limit=50'):
            call('PATCH', f"/v1/appStoreVersionLocalizations/{loc['id']}",
                 {'data': {'type': 'appStoreVersionLocalizations',
                           'id': loc['id'],
                           'attributes': {'whatsNew': args.whats_new}}})
            print(f"  what's new set for {loc['attributes'].get('locale')}")

    if not args.submit:
        print('\nnot submitted. Pass --submit to ask Apple to review it.')
        return 0

    print('creating a review submission')
    submission = call('POST', '/v1/reviewSubmissions', {
        'data': {'type': 'reviewSubmissions',
                 'attributes': {'platform': 'IOS'},
                 'relationships': {'app': {'data': {
                     'type': 'apps', 'id': app_id()}}}}})['data']
    call('POST', '/v1/reviewSubmissionItems', {
        'data': {'type': 'reviewSubmissionItems',
                 'relationships': {
                     'reviewSubmission': {'data': {
                         'type': 'reviewSubmissions', 'id': submission['id']}},
                     'appStoreVersion': {'data': {
                         'type': 'appStoreVersions', 'id': version['id']}}}}})
    call('PATCH', f"/v1/reviewSubmissions/{submission['id']}",
         {'data': {'type': 'reviewSubmissions', 'id': submission['id'],
                   'attributes': {'submitted': True}}})
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

    tf = sub.add_parser('testflight', help='distribute a build to testers')
    tf.add_argument('--build', required=True)
    tf.add_argument('--internal', action='store_true')
    tf.add_argument('--external', action='store_true')
    tf.add_argument('--group', action='append',
                    help='an exact group name; repeatable')
    tf.add_argument('--submit-beta-review', action='store_true',
                    help='required before external testers can install')
    tf.add_argument('--wait', type=int, default=45,
                    help='minutes to wait for Apple to finish processing')

    st = sub.add_parser('appstore', help='attach a build and optionally submit')
    st.add_argument('--build', required=True)
    st.add_argument('--version', required=True)
    st.add_argument('--whats-new')
    st.add_argument('--submit', action='store_true',
                    help='ask Apple to review it. This is not reversible '
                         'without a developer rejection.')
    st.add_argument('--wait', type=int, default=45)

    args = parser.parse_args()
    return {'status': cmd_status, 'metadata': cmd_metadata,
            'testflight': cmd_testflight,
            'appstore': cmd_appstore}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
