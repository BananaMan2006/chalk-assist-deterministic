# Evaluation scope · 5.1.0

This release restores an authored, deterministic controller. Its checks establish local rule behavior and packaging properties. **They do not demonstrate a live win rate, a winning streak, perfect catching, or improvement through training.** The release has no training system or shared model.

## Reproduce the checks

Use Python 3 with the pinned development dependency:

```sh
python3 -m pip install -r requirements-dev.txt
python3 run-chalk-tests.py --all --json rule-results.json
python3 run-chalk-deterministic-tests.py --json deterministic-results.json
python3 run-chalk-airborne-tests.py --json airborne-results.json
python3 -m unittest -v test_deterministic_build test_install_chalk
python3 build-chalk-script.py
git diff --exit-code -- chalk-it-up-1v1.lua chalk-autoexec-public.lua
```

`run-chalk-tests.py --suite NAME` selects individual suites. `--deps PATH` can point to a separately installed Lupa package. The CI workflow runs the same supported fixtures and checks that generated bundles match the committed sources.

## What is covered

| Area | Evidence |
| --- | --- |
| Catch planning | Reach windows, contact geometry, airborne first-contact requirements, earliest Floater contact, rejection when no airborne plan exists, and fresh pre-dive rejection |
| Tackles | Native range/clearance gates, waiting for required jump confirmation, and fresh revalidation before a dive |
| Carry moves | Repeatable choices, close-threat gates, both spin paths, stamina, cooldown and observed takeoff |
| Movement | Sprint handoffs, stationary holds, field bounds, blocker detours and avoiding steering oscillation |
| Full Auto | Authored route selection, finite rule history, control release and startup isolation |
| UI and packaging | Automation starts OFF, learner/transport modules are absent, Lua compiles, and builds are reproducible |
| Loading | Product/release guards, stale download rejection, failed-start fallback, F8 and rejoin behavior |
| Installation | Isolated destination checks, dry run, preserved unrelated files and rejection of unsafe destination layouts |

The default route tests use an authored RouteMath approximation. Field bounds are also authored test values. Numeric configuration fixtures exercise rules at explicit values; they are not evidence that the current live game's values match. An optional separately authorized RouteMath fixture can run additional local regressions through `run-chalk-deterministic-tests.py --route-math PATH`; that native source is not distributed here. The retained `chalk-fullplay-selftest.lua` supports those optional regressions.

Offline tests use ordinary Lua and double-precision math. They do not reproduce Luau scheduling, Roblox float rounding, character physics, replication delays, real input dispatch, opponents' choices, or server catch/tackle adjudication. Repeatable script decisions do not make the physical game deterministic. In particular, the game's native Spin action may select its own side; the script checks both candidate paths before requesting it.

## Live evidence still needed

A live check should record the release, mode, which features were enabled, and explicit completed-play and completed-match outcomes. Count unknown or interrupted results separately from losses. For receiving, distinguish catches, incompletes, interceptions and breakups; for defense, record catches allowed, stops and points conceded. Record sprint depletion, early arrival and collision delays when diagnosing a failed play.

Compare changes on sufficiently many similar games and keep manual and automatic play separate. Do not infer a win from a point, a catch from a requested action, or a successful tackle from an animation. Do not pool results from the removed learning system with this release. No estimate for five or ten consecutive wins is supported by the offline fixtures alone.
