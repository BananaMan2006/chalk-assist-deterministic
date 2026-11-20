# Chalk Assist · deterministic edition

Chalk Assist 5.1.12 is a rule-based Roblox client for Chalk It Up. It combines route and ball visualization, catch planning, nearby tackle attempts, collision-aware movement, and optional 1v1 Full Auto.

This edition contains **no neural policy, training loop, model downloads, shared-learning service, or learned-action selection**. It does not improve itself by playing more games. Short-lived match observations can adjust authored rules, but no knowledge is pooled across computers.

Fresh launches and manual loads start gameplay automation **OFF**. An explicitly enabled Autoplay session can continue through its own match and return teleports, carrying the current Full Auto choice. Turning it off or unloading revokes continuation; saved settings alone never enable gameplay.

Version 5.1.12 makes automatic WR routes **Floater-first**, using a deep middle stem followed by a sharp left or right cut. Floater targets sit deep in the end zone, and the predicted first catch must already be inside it. The selected depth must fit the native route, available stamina and a projected jump catch. The opening sprint can use up to 0.9 seconds of the existing two-second maximum middle-stem sprint budget, followed by normal running and a separately funded late burst. This shifts effort earlier without increasing the total planned stem sprint or spending the final catch reserve. The cut issues one sudden directional input; subsequent corrections remain smooth. Upright receiving Floaters use a checked continuous approach through contact, avoiding a modeled midair stop followed by a corrective reversal. A middle stem can continue briefly after launch only while current movement and stamina still support the catch; otherwise catch control takes over immediately. A bounded recovery burst can compensate for measured delay only when the remaining catch sprint is still funded. Short-field routes keep moving at a measured pace instead of arriving and waiting. If no funded route exists but legal deep geometry is available, an explicitly marked best-effort Floater prevents an implicit default Bullet; no catch witness is invented. This forecast does not predict an opponent's future choices.

Catch avoidance prefers a small safe bypass and uses the approach deadline to avoid unnecessary holding. Native sprint speed must be observed before an acknowledged sprint request receives full-speed reach credit. These checks do not disable jams.

Before the throw, Full Auto preserves the defensive coverage reserve. Once a live ball flight is observed, DB pursuit can spend that reserve down to the normal action/dispatch floor. This uses native speed and current stamina; it grants no extra speed or stamina. Catch selection keeps the earliest reachable airborne contact as its priority. A postthrow middle-stem continuation is released when an immediate checked catch is more than 10 ms earlier; it cannot be kept solely to seek more separation.

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
