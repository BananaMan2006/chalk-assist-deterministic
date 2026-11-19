# Chalk Assist · deterministic edition

Chalk Assist 5.1.7 is a rule-based Roblox client for Chalk It Up. It combines route and ball visualization, catch planning, nearby tackle attempts, collision-aware movement, and optional 1v1 Full Auto.

This edition contains **no neural policy, training loop, model downloads, shared-learning service, or learned-action selection**. It does not improve itself by playing more games. Short-lived match observations can adjust authored rules, but no knowledge is pooled across computers.

Fresh launches and manual loads start gameplay automation **OFF**. An explicitly enabled Autoplay session can continue through its own match and return teleports, carrying the current Full Auto choice. Turning it off or unloading revokes continuation; saved settings alone never enable gameplay.

Version 5.1.7 adds that session continuation. It uses a short-lived, single-use local teleport record, not a saved ON preference. Unsupported or unverified transitions remain OFF.

Version 5.1.6 accounts for ordinary action-dispatch delay when choosing a jump contact, rather than refining to a geometric boundary that can fail at the next input frame. The fresh-position checks remain. Local diagnostic records also distinguish explicit jam/block notices from an unexplained speed reduction.

Version 5.1.5 retains clear, funded middle-then-cut Floaters instead of replacing them with a deeper quarter route. Bullet alternatives also keep a middle stem and cut. Known failed lanes influence subsequent authored choices. Defensive recovery now detects diagonal separation while preserving stamina. Receiving favors an upright jump on Bullets that still need a run after the catch, and a confirmed carrier can attempt a checked native dive across a nearby goal line.

The 5.1.1 correction remains in place: requesting a jump no longer counts as confirmed takeoff, and an unconfirmed request is cancelled when its planned contact window has expired. The controller must replan instead of retrying that expired jump. Both roles also recheck current-position reach with the actual dispatch time before jumping; being inside the timing allowance alone is insufficient. These checks do not guarantee a catch or win.

## Load

Join Chalk It Up, attach a compatible executor, and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"))()
```

The repository is public; no GitHub token is required. Automatic loading on later joins depends on the executor's teleport queue and autoexec support. A Lua script cannot attach an executor by itself. See [installation and controls](USAGE.md).

## Behavior

- **Catch assist:** estimates reachable contacts along the observed ball flight, uses native movement and catch geometry. WR plans require a jump or jump-and-dive with sampled geometric evidence of airborne first contact. Floaters target the earliest robust airborne contact; bullets retain the downfield preference. If none is reachable, the controller can pursue without inventing a catch plan.
- **Full Auto:** chooses authored routes and defensive positioning in supported **1v1** play. It considers available stamina, opponent position, reachable timing and obstacles. Route alternatives follow deterministic rules, not random sampling or learning.
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
