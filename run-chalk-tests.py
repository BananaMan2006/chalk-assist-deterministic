#!/usr/bin/env python3
"""Execute real Chalk Lua modules with offline, data-only Roblox math fixtures."""
import argparse
import json
from pathlib import Path
import sys
import time

SUITES = (
    "planner", "approach", "tackle", "risky", "mode", "motion",
    "autoplay", "wr-repeat", "idle-guard", "fullplay-steering",
    "carrier-moves", "pending-sprint", "match-skip", "match-skip-identity",
    "autoload", "session", "avoidance", "avoidance-controller", "postthrow-stem",
)

HERE = Path(__file__).resolve().parent


def plain(value, lua_type):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [plain(value[i], lua_type) for i in range(1, len(keys) + 1)]
    return {str(k): plain(value[k], lua_type) for k in keys}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deps', type=Path, help='Optional folder containing Lupa.')
    parser.add_argument('--suite', action='append', choices=SUITES,
                        help='Repeat to select suites; default planner + approach.')
    parser.add_argument('--all', action='store_true', help='Run every supported self-contained suite.')
    parser.add_argument('--json', type=Path, help='Optional aggregate report destination.')
    args = parser.parse_args(argv)
    if args.all and args.suite:
        parser.error('Choose --all or --suite, not both')
    if args.deps:
        sys.path.insert(0, str(args.deps))
    try:
        from lupa import LuaRuntime, lua_type
    except ImportError as error:
        print(f'Lupa unavailable; install requirements-dev.txt: {error}', file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True)
    def load(path):
        path = Path(path)
        return lua.execute(path.read_text(), name=str(path))
    def one(value):
        return value[0] if isinstance(value, tuple) else value
    report = {'runtime': lua.eval('_VERSION'), 'limitations': [
        'Offline Lua with double-precision Vector3/CFrame math; Roblox float32 rounding and Luau runtime are not reproduced.',
        'No physics, replication, frame/input latency, native action execution, or server catch/tackle confirmation.',
        'Instance fixtures are isolated data tables, not simulated characters. Unsupported APIs fail.',
        'Authored field bounds and numeric configuration exercise rules; they do not verify current game dimensions or settings.'
    ], 'inputs': {
        'config': 'chalk-offline-fixture-config.lua',
        'field': 'chalk-offline-fixture-field.lua',
    }, 'suites': {}}
    try:
        load(HERE / 'chalk-offline-roblox-shim.lua')
        planner = load(HERE / 'chalk-intercept-planner.lua')
        approach = load(HERE / 'chalk-wr-approach.lua')
        config = load(HERE / 'chalk-offline-fixture-config.lua')
        field = load(HERE / 'chalk-offline-fixture-field.lua')
    except Exception as error:
        print(f'HARNESS ERROR {error}', file=sys.stderr)
        return 2
    suites = SUITES if args.all else args.suite or ['planner', 'approach']
    failed = 0
    for suite in suites:
        started = time.perf_counter()
        try:
            if suite == 'planner':
                result = load(HERE / 'chalk-intercept-selftest.lua')(planner)
            elif suite == 'approach':
                result = load(HERE / 'chalk-wr-approach-selftest.lua')(approach, planner)
            elif suite == 'risky':
                result = load(HERE / 'chalk-risky-catch-selftest.lua')(planner)
            elif suite == 'mode':
                result = load(HERE / 'chalk-mode-selftest.lua')((HERE / 'chalk-overlay-core.lua').read_text())
            elif suite == 'fullplay-steering':
                result = load(HERE / 'chalk-fullplay-steering-selftest.lua')((HERE / 'chalk-intercept-controller.lua').read_text())
            elif suite == 'postthrow-stem':
                result = load(HERE / 'chalk-postthrow-stem-selftest.lua')(planner, (HERE / 'chalk-intercept-controller.lua').read_text())
            elif suite == 'motion':
                result = load(HERE / 'chalk-character-motion-selftest.lua')(load(HERE / 'chalk-character-motion.lua'))
            elif suite == 'pending-sprint':
                result = load(HERE / 'chalk-pending-sprint-controller-selftest.lua')(
                    load(HERE / 'chalk-character-motion.lua'), (HERE / 'chalk-intercept-controller.lua').read_text())
            elif suite == 'carrier-moves':
                result = load(HERE / 'chalk-carrier-moves-selftest.lua')(load(HERE / 'chalk-carrier-moves.lua'))
            elif suite == 'autoplay':
                result = load(HERE / 'chalk-autoplay-selftest.lua')(load(HERE / 'chalk-autoplay-policy.lua'))
            elif suite == 'avoidance-controller':
                result = load(HERE / 'chalk-player-avoidance-controller-selftest.lua')((HERE / 'chalk-intercept-controller.lua').read_text(), load(HERE / 'chalk-player-avoidance.lua'))
            elif suite == 'avoidance':
                result = load(HERE / 'chalk-player-avoidance-selftest.lua')(load(HERE / 'chalk-player-avoidance.lua'))
            elif suite == 'autoload':
                result = load(HERE / 'chalk-autoload-selftest.lua')((HERE / 'chalk-bootstrap.lua').read_text(), (HERE / 'chalk-autoload-controller.lua').read_text(), (HERE / 'chalk-it-up-loader.lua').read_text())
            elif suite == 'session':
                result = load(HERE / 'chalk-session-continuity-selftest.lua')(
                    load(HERE / 'chalk-session-continuity.lua'), (HERE / 'chalk-overlay-core.lua').read_text())
            elif suite == 'match-skip':
                result = load(HERE / 'chalk-match-skip-selftest.lua')(load(HERE / 'chalk-match-skip-controller.lua'))
            elif suite == 'match-skip-identity':
                result = load(HERE / 'chalk-match-skip-identity-selftest.lua')((HERE / 'chalk-overlay-core.lua').read_text())
            elif suite == 'wr-repeat':
                result = load(HERE / 'chalk-wr-repeat-selftest.lua')(load(HERE / 'chalk-wr-repeat-controller.lua'))
            elif suite == 'idle-guard':
                result = load(HERE / 'chalk-idle-guard-selftest.lua')(load(HERE / 'chalk-idle-guard.lua'))
            elif suite == 'tackle':
                result = load(HERE / 'chalk-tackle-selftest.lua')(planner, load(HERE / 'chalk-tackle-controller.lua'), config, field)
            else:
                raise ValueError(f'Unsupported suite: {suite}')
            data = plain(one(result), lua_type)
            data['offlineSeconds'] = time.perf_counter() - started
            report['suites'][suite] = data
            if 'failed' in data:
                failed += data['failed']
                verdict = "PASS" if not data["failed"] else "FAIL"
                print(f'{suite}: {data["passed"]}/{data["total"]} {verdict} ({data["offlineSeconds"]:.3f}s)', flush=True)
                for case in data.get('results', []):
                    if not case.get('passed'):
                        print(f'  FAIL {case.get("name")}: {case.get("error")}', flush=True)
            elif isinstance(data.get('passed'), bool):
                if not data['passed']:
                    failed += 1
                print(f'{suite}: {"PASS" if data["passed"] else "FAIL"} {data.get("tests", 1)} assertions ({data["offlineSeconds"]:.3f}s)', flush=True)
            else:
                print(f'{suite}: replay completed ({data["offlineSeconds"]:.3f}s); no assertion verdict', flush=True)
                print(json.dumps(data, sort_keys=True, default=str), flush=True)
        except Exception as error:
            failed += 1
            report['suites'][suite] = {'error': str(error), 'offlineSeconds': time.perf_counter() - started}
            print(f'{suite}: ERROR {error}', flush=True)
    report['failures'] = failed
    print('LIMITATIONS: ' + ' '.join(report['limitations']), flush=True)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True, default=str) + '\n')
        print(f'Report: {args.json.resolve()}', flush=True)
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
