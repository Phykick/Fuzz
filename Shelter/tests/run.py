#!/usr/bin/env python3
"""Run the headless server tests.

Bundles the shared + server modules from ../src with tests/prelude.luau (fake Roblox APIs) and
tests/server_tests.luau into one Luau file per test, runs each in its own `luau` process (a fresh
"server"), and reports PASS / FAIL.

    python3 tests/run.py [--luau PATH] [test_name ...]
"""
import argparse
import concurrent.futures as cf
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src')
GLOBALS = ['game', 'workspace', 'task', 'os', 'warn', 'print', 'Random', 'Instance', 'Vector3', 'CFrame', 'Color3',
           'NumberRange', 'UDim2', 'Vector2', 'Enum']
# test file -> which source roots get bundled (client modules are only loaded when required)
SUITES = {
    'server_tests.luau': ['ReplicatedStorage', 'ServerScriptService'],
    'client_sound_tests.luau': ['ReplicatedStorage', 'StarterPlayer'],
}


def modules(roots):
    for root in roots:
        base = os.path.join(SRC, root)
        for dirpath, _, files in os.walk(base):
            for fn in sorted(files):
                if not fn.endswith('.lua'):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, SRC)[:-4]
                kind = 'ModuleScript'
                if rel.endswith('.server'):
                    rel, kind = rel[:-7], 'Script'
                elif rel.endswith('.client'):
                    continue
                yield rel.replace(os.sep, '.'), kind, full


def bundle(test_name, suite):
    out = ['local out = print']
    with open(os.path.join(HERE, 'prelude.luau')) as f:
        out.append('local H = (function()\n' + f.read() + '\nend)()')
    out.append('local ' + ', '.join(GLOBALS) + ' = ' + ', '.join('H.env.' + g for g in GLOBALS))
    out.append('H.services.StarterPlayer = H.newNode("StarterPlayer", "StarterPlayer")')
    for path, kind, full in modules(SUITES[suite]):
        with open(full) as f:
            src = f.read()
        src = re.sub(r'^export type ', 'type ', src, flags=re.M)
        out.append('H.define(%r, %r, function(script, require)\n%s\nend)' % (path, kind, src))
    with open(os.path.join(HERE, suite)) as f:
        out.append('local T = (function()\n' + f.read() + '\nend)()')
    out.append('T.__run(%r)' % test_name)
    return '\n'.join(out)


def test_names():
    """test name -> suite file"""
    names = {}
    for suite in SUITES:
        with open(os.path.join(HERE, suite)) as f:
            for n in re.findall(r'^T\.(\w+) = function', f.read(), flags=re.M):
                if not n.startswith('__'):
                    names[n] = suite
    return names


def run_one(luau, name, suite):
    with tempfile.NamedTemporaryFile('w', suffix='.luau', delete=False) as f:
        f.write(bundle(name, suite))
        path = f.name
    try:
        p = subprocess.run([luau, path], capture_output=True, text=True, timeout=600)
        text = p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        text = 'TIMEOUT'
    finally:
        os.unlink(path)
    ok = re.search(r'^RESULT PASS', text, flags=re.M) is not None
    return name, ok, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--luau', default=os.environ.get('LUAU', 'luau'))
    ap.add_argument('-v', '--verbose', action='store_true')
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    suites = test_names()
    names = a.tests or list(suites)
    failed = 0
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        for name, ok, text in ex.map(lambda n: run_one(a.luau, n, suites[n]), names):
            print(('PASS ' if ok else 'FAIL ') + name)
            if not ok or a.verbose:
                failed += 0 if ok else 1
                for line in text.strip().splitlines()[-25:]:
                    print('    ' + line)
    print('%d/%d passed' % (len(names) - failed, len(names)))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
