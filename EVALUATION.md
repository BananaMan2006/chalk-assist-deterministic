# Evaluation scope · 5.1.9

This release continues the authored, deterministic controller. Its checks establish local rule behavior and packaging properties. **They do not demonstrate a live win rate, a winning streak, perfect catching, or improvement through training.** The release has no training system or shared model.

## 5.1.9 scope

WR Floater plans now require airborne first contact at least 0.25 studs inside the goal line, including delayed-action samples and fresh jump/dive validation. Automatic Floater ball targets are at least four yards into the end zone. In the inspected normal field/configuration, the selected full-field route has an actual target 4.326 yards beyond goal and its unconstrained earliest forecast already touches 2.145 yards inside: the correction changes the flight, not merely a preference among catch plans. This is configuration-specific sampled/analytic evidence, not a guarantee about every opponent or future game update.

A measured startup/avoidance delay can advance a bounded recovery burst before the throw. It is capped at 0.6 seconds per route and must preserve the cost of all remaining scheduled sprint, projected catch travel and the ten-stamina reserve. Normal-running regeneration credit in route selection is limited to the opening sprint's own cost and uses the inspected rate with an added delay margin; live movement always checks actual stamina. Active recovery and late sprint intervals are unioned without treating the walking gap as sprint.

Short-field routes can continue moving at a slower pace before a sudden cut, avoiding planned parking. A native-configuration LOS matrix covering 25, 20, 15, 10, 6, 3, 1 and 0.25 yards to goal produced funded Floaters. When no funded route exists but legal deep geometry is available, a separately labeled best-effort Floater prevents the old implicit default Bullet; it carries no invented contact witness. Unknown geometry still fails closed.

Normal DB jump planning now samples up to 60 ms of action delay instead of 35 ms; WR retains 35 ms and dive delay remains 20 ms. If no normal DB plan exists, the explicitly labeled last-resort search retains a shorter 35 ms reserve and narrow contact criteria; that risky attempt is not claimed to survive 60 ms. A private replay of the conceded DB Floater showed a late plan's margin rising from 0.311 to 0.526 at the observed estimated 46.72 ms takeoff delay. The jump deadline did not move earlier, and this does not prove it fixes prior body displacement or server catch arbitration.

## Limited 5.1.9 corrected-build observation

The first three fully observed corrected-build matches each ended **4–0**. All six WR Floaters had native Catch followed by our Touchdown, with no receiving incomplete, interception or breakup in this bounded sample. Defense recorded six interceptions and one allowed catch followed by a tackle; the next down was intercepted. No runtime error was recorded. These are three observed matches, not a measured long-run win rate or a guarantee against incompletes.

The first match's second receiving play directly exercised the continuous approach: the final planned movement scale was 0.933802, and observed native planar speed was about 25.213 studs per second, consistent with 27 × that scale. Movement continued in the same direction through the observed jump samples without the earlier stop/reversal sequence. Across the first two matches, all four successful receiving first local contacts were airborne and inside the end zone; two used continuous approach and two used jump plus dive. Successes using other catch plans are not separately credited to pacing.

The allowed defensive Floater had an on-time jump request, observed takeoff and a local airborne contact claim, but the native result awarded the receiver's catch. The subsequent tackle prevented a touchdown. This is a separate unresolved contest/claim outcome, not evidence that an input was late or that local geometry guarantees server possession.

The inspected postthrow middle-stem continuations still failed the live capacity guard and yielded to catching. Thus these results validate actual receiving and the paced airborne correction, but do not establish reliable execution of the full planned twenty-yard middle stem under startup delay or avoidance. A proposed extra recovery burst was held back when its current catch-stamina check failed.

Local validation: 485 rule checks, 52 deterministic route/controller checks, 56 airborne checks and 15 build/install checks passed. These offline checks do not reproduce native physics or server arbitration.

## 5.1.9 initial live build (before the continuous-catch correction)

Two full matches ended 4–2 and 4–0, but receiving remained poor: three catches from nine Floaters, with six incompletes. All three catches had an airborne local contact observed inside the end zone, followed by native Catch and Touchdown results. Defense recorded five native interceptions, four Bullets and one Floater. Thirteen jump requests had observed takeoff, five dives were observed, and no runtime error was recorded. These wins do not establish reliable receiving.

The first missed Floater exposed an execution mismatch: the planned upright jump stopped horizontal motion before contact, but observed airborne momentum continued after zero movement input. Corrective plans assumed a rapid reversal while actual steering remained gradual. Near the predicted contact, the root was about 4.88 studs left and 2.85 studs ahead of the ball; the sampled native capsule missed by 2.74 studs. The revised grounded WR Floater forecast uses a bounded analog movement scale and continues through the contact window, with the existing action-delay, field-boundary, airborne and first-contact checks. The controller does not park or reverse that continuous witness at its target. The separate corrected-build observations above cover its initial live validation.

The initial test also returned from an owned match before any round began without preserving Autoplay. The revised handoff can arm a lobby-only ticket on an explicit same-place teleport from an owned match while automation remains enabled. It does not infer a match result; OFF, manual launch, unknown destinations and failed teleport remain excluded.

## Limited 5.1.8 local test (unpublished intermediate build)

Sixteen plays were accounted for: WR recorded six catches, two incompletes and one interception; DB recorded five interceptions, one swat and one allowed catch. Native finals were 2–0 Forfeit, 3–0 Forfeit, 4–2, and 1–0 Forfeit. Only 4–2 explicitly reaches the target score; the forfeits do not establish four-point wins. All fourteen jump requests had observed confirmation, with no runtime errors. Solve time was median 5.18 ms, 95th percentile 22.29 ms, maximum 35.00 ms.

Seven of eight selected deep-middle routes immediately lost their postthrow stem. The first had 23.56 studs left to travel but only 20.09 studs of scheduled movement before the cut, despite 100 stamina. Native sprint startup lag and lateral avoidance caused the shortfall; no explicit local jam was recorded on that play. The one continued stem produced an abrupt native movement input, but that pass was incomplete. A short-field unavailable route was followed by an unselected native Bullet, motivating the explicit short-field/fallback handling above. These findings prevented treating the intermediate build as a successful endzone-only release.

## 5.1.8 scope

Automatic receiving favors Floaters with a deep middle stem and sharp side cut. At most one step of the 20-route cycle may choose a Bullet, and only after the same route/airborne-reach checks. An infeasible Floater never triggers a Bullet fallback. This is a deterministic eligibility limit, not random sampling or a promised realized ratio. The route selector uses the interception planner to fund a jump-only catch, including limited stem sprint and final-sprint reserve. Native route sanitation may move the drawn endpoint; the led ball target is evaluated separately. Deep stems sometimes finish after native launch, so catching now permits a bounded middle-run stage only while fresh observed motion and stamina still support a future airborne catch. Cached geometry never bypasses current movement/resource checks, and losing the stage hands control to catching for the remainder of that throw.

WR dive permission is based on the root's position at dive start, not the ball-contact position. Every sampled action-delay variant and the fresh dispatch check must start in bounds and at or beyond the actual goal line. Missing goal geometry rejects WR dives. The previous carrier goal-crossing dive is removed. DB catch/tackle dives retain their existing behavior.

The sharp-cut change alters actual movement commands: a grounded WR transitioning from its middle stem can reset the retained steering heading once. This uses the existing immediate first-input path, while later corrections remain smoothed and active collision avoidance retains priority. The corresponding forecast reserves 0.12 seconds for input/physical response. It is not a proof of native velocity response under every collision or frame delay.

A private replay using the inspected native configuration and route math admits an 18-yard middle stem with a 58.51-degree route cut, a 0.6-second early sprint plus 0.6 seconds of late stem sprint, and about 15.72 predicted stamina remaining. The ball target is in the end zone, but sampled first contact occurs approximately 0.79 yards short during an upright jump; this is not labeled an in-zone catch. An authored stationary blocker replay admits a 17.5-yard variant. These are offline forecasts, not live outcomes.

Offline tests are authored geometry and mocked lifecycle checks, not evidence of a native catch or improved win rate. Live verification for this release is recorded separately below when observed. The older results remain historical, including losses and incompletes.

## 5.1.7 scope

Autoplay can carry an explicitly enabled session through its own match and return teleports. Constructors still start OFF. A short-lived local record must be validated and consumed before resuming; a manual load, explicit OFF or unload takes precedence. This release changes session lifecycle, not the catch geometry or route strategy. The unresolved movement limitation below remains.

These lifecycle properties depend on functioning native teleport-setting storage. If arming succeeds but a later cancellation write fails, the earlier record may remain until expiry; failure is reported rather than treated as confirmed revocation. Old executor queues can also retain a pre-upgrade loader for one hop. A clean join is needed for the upgrade test. Queue provenance and the destination's match/lobby kind are checked; the observed client queue packets do not provide a specific destination server or opponent identity.

## Limited 5.1.7 observation

After one upgrade rejoin with automation OFF, Full Auto and Autoplay were explicitly enabled once. The client entered its queued match, completed it, returned to the lobby and entered another match without an enable helper or manual reload. Read-only status captures showed a consumed match continuation, an armed lobby return, and a consumed continuation in the next match. The short lobby interval was verified through load/enable records and the subsequent automatic match entry rather than a separate lobby status capture.

The completed match ended **4–0** across six throws. All three WR passes were caught: two were followed by touchdowns and one by a tackle. Defense recorded one interception, one opponent catch followed by a successful tackle, and one opponent incomplete. The latter two outcomes are not counted as breakups. The allowed catch followed an on-time local dive and a local contact claim; the server still awarded the opponent's catch. Four catch-jump requests had observed takeoff, with no fresh-jump rejection, late request or runtime error. Solve time had median 20.3 ms, 95th percentile 40.9 ms and maximum 55.8 ms. Local jam notices occurred on the receiving plays. These observations validate this session round-trip, not perfect play. The automatically started next match subsequently ended 2–4, so this scoreline is not evidence of consistent winning.

The second 5.1.7 match contained nine complete plays: WR recorded three catches and two incompletes; DB recorded one interception and three opponent catches, two followed by touchdowns and one by a tackle. One missed WR Bullet was first observed by the throw receiver about 1.67 seconds after its launch, beyond its 1.05-second flight; the underlying delivery delay is not established. Another receiving Floater became unreachable after an explicit local jam notice and a roughly 0.90-second native speed reduction from 27 to 12.15. Neither failure was a late jump request. Automatic continuation again survived the completed loss and entered the next match without an active-play reload.

## 5.1.6 scope

Contact-time robustness alone did not cover late action dispatch. A recorded Floater plan had a worst sampled margin of about 0.401 studs against the required 0.4; an otherwise ideal jump just 0.6 ms late fell below that threshold and was cancelled. Planning now checks a bounded action-delay envelope without reducing the required contact margin or bypassing fresh-position validation. The observations motivating the budget include up to roughly 16 ms of request delay and 18 ms until observed takeoff; the latter includes observation latency. A sampled envelope does not cover arbitrarily long stalls or prove continuous collision safety.

Local diagnostic records distinguish explicit client-relative jam/block notices from an inferred slowdown. These records retain only the local state and event type, not the original packet body or player identities.

## Limited 5.1.6 observation

One fully observed match ended **4–0** across six throws. Both WR Floaters (one quarter start, one middle stem) produced native catches followed by our touchdowns. The latter also included an observed carrier finish dive before the native touchdown. Defense recorded three breakups and one opponent Floater incomplete; that incomplete is not counted as an interception. All five catch-jump requests had observed takeoff, with no fresh-jump rejection, late input request or runtime error. Fifty native solves had median 8.7 ms, 95th percentile 31.4 ms and maximum 32.4 ms. No jam/block notice occurred. This is one clean match, not evidence of a long-run win rate or immunity to slowdown/steering failures.

A second fully observed match also ended **4–0**, but included one receiving Floater incomplete. The next middle Floater and a middle Bullet were caught and followed by touchdowns; both scoring sequences included an observed carrier finish dive. Defense recorded one interception, one breakup and one opponent incomplete. All four catch-jump requests had observed takeoff. One fresh jump check rejected a Bullet plan, and a replacement plan recovered to a catch. There were no late action requests or runtime errors. Sixty-seven solves had median 6.9 ms, 95th percentile 23.2 ms and maximum 52.4 ms.

The missed Floater lost its early jump-and-dive opportunity while collision avoidance steered around a close defender and withheld sprint. No jump was requested, and there was no fresh-jump rejection or explicit jam/block notice on that play. Recorded-position replays did not support simply switching passing sides or cutting slightly earlier. The straight-line catch forecast does not account for the full detour. This remains an unresolved movement/planning limitation. Two 4–0 scorelines are not two matches without receiving failures, and do not establish a win rate.

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
| UI and packaging | Fresh/manual starts remain OFF, learner/transport modules are absent, Lua compiles, and builds are reproducible |
| Loading | Product/release guards, stale download rejection, failed-start fallback, F8 and verified session continuation |
| Installation | Isolated destination checks, dry run, preserved unrelated files and rejection of unsafe destination layouts |

The default route tests use an authored RouteMath approximation. Field bounds are also authored test values. Numeric configuration fixtures exercise rules at explicit values; they are not evidence that the current live game's values match. An optional separately authorized RouteMath fixture can run additional local regressions through `run-chalk-deterministic-tests.py --route-math PATH`; that native source is not distributed here. The retained `chalk-fullplay-selftest.lua` supports those optional regressions.

Offline tests use ordinary Lua and double-precision math. They do not reproduce Luau scheduling, Roblox float rounding, character physics, replication delays, real input dispatch, opponents' choices, or server catch/tackle adjudication. Repeatable script decisions do not make the physical game deterministic. In particular, the game's native Spin action may select its own side; the script checks both candidate paths before requesting it.

## Live evidence still needed

A live check should record the release, mode, which features were enabled, and explicit completed-play and completed-match outcomes. Count unknown or interrupted results separately from losses. For receiving, distinguish catches, incompletes, interceptions and breakups; for defense, record catches allowed, stops and points conceded. Record sprint depletion, early arrival and collision delays when diagnosing a failed play.

Compare changes on sufficiently many similar games and keep manual and automatic play separate. Do not infer a win from a point, a catch from a requested action, or a successful tackle from an animation. Do not pool results from the removed learning system with this release. No estimate for five or ten consecutive wins is supported by the offline fixtures alone.
