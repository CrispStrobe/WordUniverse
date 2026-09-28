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
    return {'status': cmd_status, 'testflight': cmd_testflight,
            'appstore': cmd_appstore}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
