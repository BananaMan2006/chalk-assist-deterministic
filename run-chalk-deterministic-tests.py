#!/usr/bin/env python3
"""Run deterministic Full Auto isolation and the retained physics-policy regressions."""
import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deps', type=Path, default=Path('/private/tmp/chalk-replay-deps'))
    parser.add_argument('--route-math', type=Path,
                        help='Authorized local native RouteMath; never copied into reports.')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.deps))
    from lupa import LuaRuntime, lua_type
    lua = LuaRuntime(unpack_returned_tuples=True)
    def load(name):
        return lua.execute((HERE / name).read_text(), name=name)
    def plain(value):
        if lua_type(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [plain(value[index]) for index in range(1, len(keys) + 1)]
        return {str(key): plain(item) for key, item in value.items()}
    load('chalk-offline-roblox-shim.lua')
    policy = load('chalk-fullplay-policy.lua')
    controller = load('chalk-fullplay-controller.lua')
    planner = load('chalk-intercept-planner.lua')
    route_source = args.route_math.read_text() if args.route_math else (HERE / 'chalk-deterministic-route-fixture.lua').read_text()
    pure = (HERE / 'chalk-fullplay-selftest.lua').read_text()
    suites = {
        'defensive-cuts': plain(load('chalk-defensive-cut-selftest.lua')(policy)),
        'scheduled-route-mix': plain(load('chalk-deterministic-route-mix-selftest.lua')(policy, controller, route_source, planner)),
        'deterministic-isolation': plain(load('chalk-deterministic-fullplay-selftest.lua')(policy, controller, route_source, planner)),
    }
    if args.route_math:
        suites['retained-policy'] = plain(lua.execute(pure, name='retained-policy-fixture')(
            policy, controller, route_source, (HERE / 'chalk-fullplay-policy.lua').read_text()))
    failed = 0
    for name, report in suites.items():
        print(f'{name}: {report["passed"]}/{report["total"]} PASS')
        failed += report['failed']
        for item in report['results']:
            if not item['passed']:
                print(f'  FAIL {item["name"]}: {item.get("error")}')
    output = {'schemaVersion': 1, 'syntheticOnly': True,
              'limitations': ['Offline authored math/services; no Roblox physics, network, or live win proof.'],
              'suites': suites}
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(output, indent=2) + '\n')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
