# Evaluation scope · 5.1.6

This release continues the authored, deterministic controller. Its checks establish local rule behavior and packaging properties. **They do not demonstrate a live win rate, a winning streak, perfect catching, or improvement through training.** The release has no training system or shared model.

## 5.1.6 scope

Contact-time robustness alone did not cover late action dispatch. A recorded Floater plan had a worst sampled margin of about 0.401 studs against the required 0.4; an otherwise ideal jump just 0.6 ms late fell below that threshold and was cancelled. Planning now checks a bounded action-delay envelope without reducing the required contact margin or bypassing fresh-position validation. The observations motivating the budget include up to roughly 16 ms of request delay and 18 ms until observed takeoff; the latter includes observation latency. A sampled envelope does not cover arbitrarily long stalls or prove continuous collision safety.

Local diagnostic records distinguish explicit client-relative jam/block notices from an inferred slowdown. These records retain only the local state and event type, not the original packet body or player identities.

## Limited 5.1.6 observation

One fully observed match ended **4–0** across six throws. Both WR Floaters (one quarter start, one middle stem) produced native catches followed by our touchdowns. The latter also included an observed carrier finish dive before the native touchdown. Defense recorded three breakups and one opponent Floater incomplete; that incomplete is not counted as an interception. All five catch-jump requests had observed takeoff, with no fresh-jump rejection, late input request or runtime error. Fifty native solves had median 8.7 ms, 95th percentile 31.4 ms and maximum 32.4 ms. No jam/block notice occurred. This is one clean match, not evidence of a long-run win rate or immunity to slowdown/steering failures.

## Limited 5.1.5 observation

The first observed match ended **3–4** across twelve throws. Seven WR passes included six Floaters: one had confirmed takeoff, an airborne dive, a native Catch and our touchdown; five were incomplete. The Bullet was caught and then tackled. Defense allowed two catches, broke up one pass and intercepted two. Full Auto enabled eight milliseconds after the first PreSnap, so opening setup coverage was partial. All receiving routes were submitted by Full Auto.

Two Floater failures involved fresh-jump geometry rejection after stable movement; another lacked enough remaining jump-to-dive time at dispatch. Two began with the native 0.45 speed factor near another body, but no explicit jam/block notice was then recorded, so the cause was not established. One allowed DB catch also involved jump validation; the other involved prethrow separation and turning delay. Five catch jumps had observed takeoff, four airborne dives were observed, and one carrier jump was observed. No finish dive was attempted. No runtime errors or late input requests were recorded. The loss and individual failures remain part of the evaluation; the successful Floater alone does not establish reliability.

## 5.1.5 scope

The route selector no longer replaces a clear, funded middle Floater merely because a different, longer middle candidate is blocked. Quarter starts are Floater-only; Bullet alternatives retain a middle stem and cut. Known interceptions and breakups join incompletes in failed-lane penalties. A DB recovery rule uses measured opening separation to recognize diagonal sprinting before the older per-axis emergency thresholds; ordinary bursts retain 85-start / 70-stop stamina limits.

Receiving can prefer an upright jump for a Bullet targeted short of the goal. A native finish-dive attempt after confirmed possession requires a nearby goal crossing, field/collision clearance and an estimated opponent reach check. Neither change guarantees avoiding a tackle. The existing earliest robust airborne Floater objective and current-position jump/dive revalidation remain.

## 5.1.4 scope

A materially changed movement target ends the previous avoidance path's brief hold, while keeping bounded turns and collision checks. Small requested-direction jitter retains the existing hold. The change addresses observed stale steering after a temporary native slowdown; it does not remove that slowdown or guarantee that a lost catch can be recovered.

## Limited 5.1.4 observation

The first observed match ended with a native Forfeit at a 3–1 score, with a four-point target; it is not counted as a completed four-point win, and the logged forfeit fields did not establish a winner. Five passes were thrown: three WR Bullet catches (two followed by touchdowns, one by a tackle), one DB Bullet interception and one opponent Bullet catch followed by a touchdown. The last receiving touchdown followed a route-unavailable result without a submitted Full Auto route, so it is not attributed to automatic route selection. No WR Floater occurred.

All five requested jumps had observed takeoff, and two dives had observed airborne dispatch. No late action or runtime error was recorded. On the conceded touchdown, the defender had fallen behind before the throw; a subsequent local catch claim was not accepted as a native catch for our player. The server rejection reason is unknown. This remains a limitation under investigation, not proof that catch timing is correct.

A second fully observed 5.1.4 match ended **4–2**, with ten throws. WR outcomes were two catches (one followed by a tackle, one by a touchdown), two interceptions and one breakup. DB outcomes were two interceptions and three breakups. All five receiving routes were quarter Bullets; four had overridden the nominal middle preference. The two interceptions involved repeated position-drift replans and loss of a valid jump window; the breakup followed a jump and a local catch claim that was not awarded. Eight requested jumps had observed takeoff, five airborne dives were observed, and no late input or runtime error was recorded. No WR Floater occurred. This result motivated the route-selection correction, but does not establish improvement.

The catch forecast currently assumes immediate approach steering, whereas actual turns are bounded. An isolated turn-aware replay invalidated one early witness and found a later one; this prototype is not part of 5.1.5 and is not a live catch result. Native catch/tackle adjudication can also disagree with local geometric estimates. These remain known limitations.

## Limited 5.1.3 observations

Two fully observed test matches ended **4–0** and **4–1**. The first had two WR Catch→Touchdown sequences and two DB Intercepted→our-point sequences; both receiving passes were Bullets. The second contained seven plays: three WR Bullet catches (two followed by tackles and one by a touchdown), one WR Floater incomplete, two DB Bullet interceptions and one DB Floater interception. Native point/score packets support the outcome sequences; ball-result packets did not explicitly identify the catcher.

The missed WR Floater had a native speed reduction before and just after the throw. While slowed, movement-only pursuit aimed toward an early ball position behind the runner. After speed recovered, two reachable jump-and-dive forecasts appeared, but avoidance temporarily held the previous direction and the opportunity was lost before takeoff. No jump or dive was dispatched on that play. The old target's hold continuing after the new catch direction motivated the 5.1.4 correction; detailed recordings remain private. A later DB Floater was intercepted with a native ground dive. That result does not verify airborne WR Floater execution.

## 5.1.3 scope

The change addresses mid-stem obstruction and timing debt: a slow or stationary defender at least four yards up the intended stem can trigger an alternate family when its estimated walking detour does not fit. The alternative must be clear and retain equal or better estimated defender clearance. Ordinary nearby coverage remains eligible for a middle route. Slower movement is permitted only when the current distance can still be covered before the cut deadline. Explicit incompletes discourage the failed pass/side, and repeated incompletes can change the family; unknown outcomes are ignored. The earlier bounded DB recovery bursts and feasible Floater-majority mix remain. Live improvement from 5.1.3 has not yet been established.

## Limited 5.1.2 observation

The first observed test match ended **4–2**, with Full Auto enabled before its first PreSnap. It still produced **three WR incompletes**; a winning final score does not demonstrate that the route changes improved receiving or establish a win rate. Six jump requests had observed takeoff, four airborne dives showed the expected native state, and no late jump retry was logged.

The three failed Floaters were unreachable at the first ball plan. Sprint speed stayed 27 after the throw. Before the throw, the sampled stem progress was only 32–38 studs over about 2.7 seconds, against roughly 54 studs assumed by the route timing. Slower pacing and blocker avoidance spent the available time, but the scheduled cut and throw continued. This is an observed execution-versus-planning mismatch, distinct from the native speed reduction in the earlier test. It motivated the 5.1.3 correction; detailed records remain private.

## Limited 5.1.1 observation

One native completed-match record showed a **4–2 win**. Full Auto was enabled midmatch, so this is not an eligible fully observed automatic win or streak, and one match cannot establish a win rate. Five jump requests had matching observed takeoffs; four airborne dive requests were followed by the native dive state. Those action observations alone are not proof of catches.

The match included a WR incomplete while native movement speed fell from 27 to 12.15 for about 0.92 seconds. Full steering and substantial stamina were still present; the lost travel made the planned catch unreachable. The logs do not establish whether a jam caused the slowdown. Detailed runtime records remain private, and no player names or identifiers are published here.

## 5.1.1 correction

An unconfirmed WR or DB jump request could previously be retried after its planned contact had already elapsed because a request-sent flag was treated as takeoff progress. This patch cancels that expired request and requires replanning. The regression target covers delayed or absent takeoff, elapsed contact before retry, and ordinary still-valid jump confirmation. Both roles also validate current-pose catch geometry with takeoff shifted to the actual dispatch time. A jump can remain inside the 75 ms allowance yet be geometrically too late. A sent input alone is not an observed action or a catch.

The correction has no established live effect on catches or wins. Automation still starts OFF. First-contact checks sample geometric predictions; they are not continuous collision proofs or Roblox/server guarantees. Offline solving time also does not establish a live frame budget; live `solveMs` and dispatch timing still need observation.

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
