#!/usr/bin/env python3
"""Upload the sound atlas to Roblox and wire its asset id into the game.

    python3 tools/upload_sounds.py --api-key KEY --user-id 123456
    python3 tools/upload_sounds.py --api-key KEY --group-id 7654321   # group-owned games

Needs an Open Cloud API key with Assets read + write (create.roblox.com > Open Cloud >
API Keys). Uploads audio/underhaven_sounds.ogg as an Audio asset, waits for Roblox to finish
processing it, writes the id into src/ReplicatedStorage/Shared/SoundBank.lua and rebuilds
Shelterv1-fixed.rbxl. Upload as the same user or group that owns the game, or the game won't
be allowed to play it.

Prefer clicking? Upload the .ogg in Studio or on the Creator Hub instead and paste the id into
SoundBank.ATLAS_ID by hand (see README).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
API = 'https://apis.roblox.com/assets/v1'
OGG = os.path.join(ROOT, 'audio', 'underhaven_sounds.ogg')
BANK = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'Shared', 'SoundBank.lua')


def call(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method, headers={'x-api-key': key})
    if content_type:
        req.add_header('Content-Type', content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        raise SystemExit('Roblox said %d: %s' % (e.code, e.read().decode(errors='replace')))


def upload(key, creator):
    request = {
        'assetType': 'Audio',
        'displayName': 'Underhaven sounds',
        'description': 'Underhaven sound effects and ambience atlas',
        'creationContext': {'creator': creator},
    }
    boundary = uuid.uuid4().hex
    with open(OGG, 'rb') as f:
        audio = f.read()
    body = b''.join([
        ('--%s\r\nContent-Disposition: form-data; name="request"\r\n\r\n' % boundary).encode(),
        json.dumps(request).encode(), b'\r\n',
        ('--%s\r\nContent-Disposition: form-data; name="fileContent"; filename="underhaven_sounds.ogg"\r\n'
         'Content-Type: audio/ogg\r\n\r\n' % boundary).encode(),
        audio, b'\r\n',
        ('--%s--\r\n' % boundary).encode(),
    ])
    op = call('POST', API + '/assets', key, body, 'multipart/form-data; boundary=' + boundary)
    op_id = op.get('operationId') or op.get('path', '').split('/')[-1]
    for _ in range(60):
        if op.get('done'):
            break
        time.sleep(3)
        op = call('GET', '%s/operations/%s' % (API, op_id), key)
    if not op.get('done'):
        raise SystemExit('Upload still processing after 3 minutes (operation %s); try again later.' % op_id)
    asset_id = (op.get('response') or {}).get('assetId')
    if not asset_id:
        raise SystemExit('Upload finished without an asset id: %s' % json.dumps(op))
    return asset_id


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--api-key', default=os.environ.get('ROBLOX_API_KEY'), required=os.environ.get('ROBLOX_API_KEY') is None)
    owner = ap.add_mutually_exclusive_group(required=True)
    owner.add_argument('--user-id')
    owner.add_argument('--group-id')
    a = ap.parse_args()
    creator = {'userId': a.user_id} if a.user_id else {'groupId': a.group_id}
    asset_id = upload(a.api_key, creator)
    print('Uploaded: rbxassetid://%s' % asset_id)
    src = open(BANK).read()
    src, n = re.subn(r'SoundBank\.ATLAS_ID = "[^"]*"', 'SoundBank.ATLAS_ID = "rbxassetid://%s"' % asset_id, src)
    if n != 1:
        raise SystemExit('Could not find SoundBank.ATLAS_ID in ' + BANK)
    with open(BANK, 'w') as f:
        f.write(src)
    subprocess.run([sys.executable, os.path.join(HERE, 'build_place.py'),
                    os.path.join(ROOT, 'Shelterv1.rbxl'), os.path.join(ROOT, 'Shelterv1-fixed.rbxl')], check=True)
    print('Done: SoundBank.ATLAS_ID set and Shelterv1-fixed.rbxl rebuilt.')


if __name__ == '__main__':
    main()
