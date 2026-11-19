#!/usr/bin/env python3
"""Offline airborne catch geometry and controller guard regressions."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deps', type=Path, default=Path('/private/tmp/chalk-replay-deps'))
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.deps))
    from lupa import LuaRuntime, lua_type
    lua = LuaRuntime(unpack_returned_tuples=True)
    def load(name): return lua.execute((ROOT / name).read_text(), name=name)
    def plain(value):
        if lua_type(value) != 'table': return value
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys)+1)):
            return [plain(value[i]) for i in range(1, len(keys)+1)]
        return {str(k): plain(v) for k,v in value.items()}
    load('chalk-offline-roblox-shim.lua')
    result = plain(load('chalk-airborne-catch-selftest.lua')(load('chalk-intercept-planner.lua'),
                    (ROOT / 'chalk-intercept-controller.lua').read_text()))
    print(f'Airborne catch: {result["passed"]}/{result["total"]} PASS')
    for item in result['results']:
        if not item['passed']: print('FAIL', item['name'], item['error'])
    if args.json:
        args.json.parent.mkdir(parents=True,exist_ok=True)
        args.json.write_text(json.dumps({'syntheticOnly': True, 'results': result,
            'limitations': ['Authored geometry and mocked controller guards; no native catch or win proof.']}, indent=2)+'\n')
    return int(result['failed']>0)

if __name__ == '__main__':
    raise SystemExit(main())
