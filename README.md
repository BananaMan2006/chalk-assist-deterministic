# Chalk Assist · deterministic edition

Chalk Assist 5.1.28 is a rule-based Roblox client for Chalk It Up. It combines route and ball visualization, catch planning, nearby tackle attempts, collision-aware movement, and optional 1v1 Full Auto.

Version 5.1.28 compares both passing sides at the start of a receiving catch approach when a nearby player blocks the direct path. A short, bounded forecast includes the time spent turning and uses current movement speed without crediting a future sprint acknowledgement. It changes sides only when both forecasts are valid and the alternative makes more checked progress toward the catch. The chosen side remains stable on subsequent frames. Prethrow routes, defensive positioning, stamina limits and catch permissions retain their existing rules. This reduces a reproduced detour cost; it cannot guarantee possession against a reacting opponent.

This edition contains **no neural policy, training loop, model downloads, shared-learning service, or learned-action selection**. It does not improve itself by playing more games. Short-lived match observations can adjust authored rules, but no knowledge is pooled across computers.

Settings are saved locally and restored on rejoins, manual loads and later launches. This includes the master switch, assist, Full Auto, Autoplay, WR-pad repeat and Auto Leave, plus mode, usernames, alerts and window layout. Previously selected ON switches resume automatically. New installations start gameplay automation OFF. Unloading stops the current runtime without replacing saved choices with OFF; turn a switch OFF to save that choice. Settings are not shared between computers.

Version 5.1.12 makes automatic WR routes **Floater-first**, using a deep middle stem followed by a sharp left or right cut. Floater targets sit deep in the end zone, and the predicted first catch must already be inside it. The selected depth must fit the native route, available stamina and a projected jump catch. The opening sprint can use up to 0.9 seconds of the existing two-second maximum middle-stem sprint budget, followed by normal running and a separately funded late burst. This shifts effort earlier without increasing the total planned stem sprint or spending the final catch reserve. The cut issues one sudden directional input; subsequent corrections remain smooth. Upright receiving Floaters use a checked continuous approach through contact, avoiding a modeled midair stop followed by a corrective reversal. A middle stem can continue briefly after launch only while current movement and stamina still support the catch; otherwise catch control takes over immediately. A bounded recovery burst can compensate for measured delay only when the remaining catch sprint is still funded. Short-field routes keep moving at a measured pace instead of arriving and waiting. If no funded route exists but legal deep geometry is available, an explicitly marked best-effort Floater prevents an implicit default Bullet; no catch witness is invented. This forecast does not predict an opponent's future choices.

Version 5.1.14 can fund a smaller middle-stem recovery sprint when the entire requested burst would exceed the reserved catch budget. The total extra recovery remains capped at 0.6 seconds and cannot begin after the throw. It also lets defense spend its coverage reserve while chasing a verified opposing ball carrier after the catch; setup still preserves stamina. Fast sideways defensive recovery also no longer stops solely because the receiver has a small backward component; its existing stamina limits and coverage targets remain. These changes do not guarantee recovery from a jam or an existing large gap.

Version 5.1.27 separates the centered-pressure starting-side cycle from the final cut-side cycle. An alternative cut must already exist at the same deep stem and preserve width, funding, catch timing, estimated defender coverage and recent failure history. Off-center blockers still receive the existing away-side setup. This removes a repeated starting-side cue without accepting a worse modeled catch. Passive jump-request diagnostics also distinguish a requested jump from actual takeoff; they do not force a dive when native airborne permission is absent.

Version 5.1.26 clears an old movement heading when a new navigation request follows an explicit zero-input physical stop on the same character. The character must still be grounded and stopped, with no ball flight or committed jump/dive. Fresh collision checks still choose the restart path. Moving reversals and blocked nonzero input keep their bounded turning behavior. This corrects a reproduced wrong-way defensive restart after a short stop.

Version 5.1.25 can choose a legal starting position 1.5 yards off center when a defender can crowd the middle during setup. It still runs toward the deep middle cut and requires the full route and catch to fit the stamina budget; one centered fallback remains available. Live-ball pursuit keeps finer checked detours when no catch is currently reachable. Before a defensive airborne dive, a conservative current-position check cancels only when the modeled dive cannot touch the ball anywhere in the remaining bounded flight; uncertain cases retain the existing plan. Frame-gap records now include native focus events and heartbeat cadence. These changes do not prevent every block or turn a local touch into server-awarded possession.

Version 5.1.24 rejects diving plans whose first catch contact disappears during the body’s tilt before the later checked catch window. Moving DB Floater jumps that previously required stopping in midair now use a bounded, paced approach through contact; stationary setups and Bullet behavior remain unchanged. Confirmed local upright contact can retain only its original movement briefly, with the same field, body, stamina and ownership checks. A separate movement correction avoids applying the walking speed reduction twice to an already-paced input. New frame-gap diagnostics help distinguish delayed gameplay updates from ordinary missed timing.

Version 5.1.23 starts a shallow collision-checked bypass earlier during the native opening jam window. It applies only to a current, grounded WR route before the throw, and preserves later catch steering. Against middle pressure, route selection can shift 0.15 seconds of its existing late sprint to the opening (1.05 seconds rather than 0.9), retaining the old allocation if the changed timing loses a funded catch. Total planned stem sprint and final catch reserve do not increase. This is ordinary movement, not protection from the native jam mechanic.

Version 5.1.22 compares actual sanitized target and airborne catch width before settling for a narrow deep route. A bounded search can select a wider funded catch while retaining a deep middle run, native bounds, end-zone contact and final sprint reserve. It keeps a reachable inset route when no admitted wider alternative exists. Extra local diagnostics record the actual avoidance turn and native knockdown effects; they do not change movement or catch claims.

Version 5.1.21 corrects a numerical edge case in defensive lateral reversals and adds recovery during the first 0.4–1.5 seconds for a large sideways gap when the receiver has already turned upfield. It retains the native turn rate and existing sprint reserves. This improves specific coverage decisions without claiming that every throw is interceptable.

Version 5.1.20 allows a checked sprint escape from a moving nearby player only when measured normal movement is already occurring and both native-speed paths strictly increase separation. Stationary bodies, jams and unsafe crossings remain ineligible. After a fresh local contact claim, a confirmed upright WR catch can also finish its original continuous movement for a scheduled maximum of 150 ms, bounded by the original stop time and fresh ownership, motion, field and clearance checks. Expiry is checked on each controller frame, so actual release can occur slightly after the scheduled time. It sends no extra catch request or action, and an authoritative result cancels it immediately. Local contact is still not proof of possession.

Version 5.1.19 also preserves an already-funded WR route sprint through a checked prethrow bypass. This requires the current submitted route, its observed start time and a finite future waypoint deadline; ordinary walking, stale routes and defensive setup do not gain this permission. The actual path must still pass both speed checks and the existing clearance and stamina gates.

Version 5.1.18 corrects receiving route stamina accounting. Pre-snap route forecasts keep a conservative setup allowance, based on observed lower stamina at live starts; this is an empirical planning assumption, not a claimed server rule. Forecasts include only regeneration that fits the native recovery interval and remaining stamina capacity. Extra recovery sprint is charged only for observed sprint intervals, so a blocked request does not consume the whole correction allowance. When a checked sprint bypass is permitted, its forecast now preserves the same clearance band that the next-frame sprint gate requires, reducing avoidable sprint/walk toggles during crossings. Routes still preserve the final catch reserve and require the existing airborne catch checks.

Version 5.1.17 preserves a checked WR sprint when a pending native-speed update temporarily changes a reachable catch into pursuit. Collision bypasses now compare forward progress at the speeds they can safely use, so a slightly wider same-side sprint path can beat a shallow path that forces walking. The actual bounded turn still has to pass clearance, field bounds, stamina and contact checks. Fresh airborne-dive rejection logs now retain the actual pose and timing needed to replay that failure. These corrections do not relax catch validation or establish that a missed play would become a catch.

Version 5.1.16 lets DB live-ball pursuit retain a collision-checked sprint even when no current catch witness exists. A temporarily unreachable forecast no longer forces a safe bypass back to walking. This gives no extra reach credit: the actual/prospective speed checks, stamina budget, grounded state and action priority remain.

Version 5.1.15 removes an unsafe contact fallback: if every checked speed on the current turning heading fails clearance, translation stays at zero while the bounded turn continues. Movement resumes as soon as a checked heading can escape. An already-safe exit is not delayed. This prevents unchecked forward pushing inside an overlap; it does not disable native jams.

Catch avoidance prefers a small safe bypass and uses the approach deadline to avoid unnecessary holding. Native sprint speed must be observed before an acknowledged sprint request receives full-speed reach credit. These checks do not disable jams.

Before the throw, Full Auto preserves the defensive coverage reserve. Once a live ball flight is observed, DB pursuit can spend that reserve down to the normal action/dispatch floor. A reachable interception can retain sprint while taking a collision-checked detour, just like a receiving catch; touching, blocked or unsafe paths still release sprint. This uses native speed and current stamina; it grants no extra speed or stamina. Catch selection keeps the earliest reachable airborne contact as its priority. A postthrow middle-stem continuation is released when an immediate checked catch is more than 10 ms earlier; it cannot be kept solely to seek more separation.

WR dives must start **inside the end zone**. Planning, delayed-action samples and the final observed-position check enforce that boundary. A catch beyond the goal does not permit a dive that starts before it. The old carrier dive across the goal line has been removed. Upright jumps and DB interception/tackle actions remain available.

Session continuation from 5.1.7 and the bounded action-dispatch timing checks from 5.1.6 remain in place. Local diagnostics distinguish explicit jam/block notices from an unexplained speed reduction.

The 5.1.1 correction remains in place: requesting a jump no longer counts as confirmed takeoff, and an unconfirmed request is cancelled when its planned contact window has expired. The controller must replan instead of retrying that expired jump. Both roles also recheck current-position reach with the actual dispatch time before jumping; being inside the timing allowance alone is insufficient. These checks do not guarantee a catch or win.

## Load

Join Chalk It Up, attach a compatible executor, and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"))()
```

The repository is public; no GitHub token is required. Automatic loading on later joins depends on the executor's teleport queue and autoexec support. A Lua script cannot attach an executor by itself. See [installation and controls](USAGE.md).

## Behavior

- **Catch assist:** estimates reachable contacts along the observed ball flight, uses native movement and catch geometry. WR plans require a jump or jump-and-dive with sampled geometric evidence of airborne first contact. WR Floaters target the earliest robust airborne contact inside the end zone; DB still targets the earliest reachable interception. Bullets retain the downfield preference. If none is reachable, the controller can pursue without inventing a catch plan.
- **Full Auto:** chooses authored routes and defensive positioning in supported **1v1** play. Automatic receiving normally chooses Floaters with a deep middle stem and a sharp side cut. One Bullet counter is eligible per opponent session, as soon as two completed plays show sustained deep, stationary defense and that coverage remains present. It no longer waits for a fixed route-cycle slot; unavailable candidates and failed submissions do not spend the attempt. It keeps the deep middle run and hard side cut, requires a moving airborne catch short of goal plus clear observed run-in space, and reserves stamina for a carrying move. It considers available stamina, opponent position, reachable timing and obstacles. Route alternatives follow deterministic rules, not random sampling or learning.
- **Tackles and carrying:** attempts available native actions near a genuine threat, with range, clearance, stamina and cooldown checks.
- **Optional helpers:** autoplay with a mode selector, return to the nearest WR pad, saved auto-leave username lists, and match-alert settings.
- **Window controls:** drag, minimize, Right Shift to hide/show, and F8 to unload.

Full Auto's 1v1 restriction is separate from the autoplay mode selector. Selecting a team mode does not add team Full Auto support. The server still decides catches, tackles, scores and wins; predicted reach is not a guarantee.

## Source and checks

The runtime is assembled from an explicit module list in [build-chalk-script.py](build-chalk-script.py). The generated release is [chalk-it-up-1v1.lua](chalk-it-up-1v1.lua). The repository does not ship extracted game scripts, account credentials, private runtime recordings or training state.

```sh
python3 -m pip install -r requirements-dev.txt
python3 run-chalk-tests.py --all
python3 run-chalk-deterministic-tests.py
python3 run-chalk-airborne-tests.py
python3 -m unittest -v test_deterministic_build test_install_chalk
python3 build-chalk-script.py
```

The tests exercise authored offline fixtures and the actual Lua modules. They do not reproduce Roblox physics, networking or server decisions. Live outcomes and failures are retained in the [evaluation report](EVALUATION.md), including a 5.1.5 loss and two subsequent 5.1.6 wins at 4–0. The second of those wins still had one receiving Floater incomplete caused by lost travel during a blocker detour. A winning score does not demonstrate perfect receiving or establish a win rate.
