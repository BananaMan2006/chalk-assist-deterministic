# Running Chalk Assist 5.1.7

The public repository is [BananaMan2006/chalk-assist-deterministic](https://github.com/BananaMan2006/chalk-assist-deterministic). The ready-to-run file is `chalk-it-up-1v1.lua`.

## Start on a computer

Join Chalk It Up, attach your executor, and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"))()
```

The executor must support HTTP requests and `loadstring`. No GitHub account or token is needed. Verify **5.1.7** in the window's release badge. Gameplay automation starts OFF after a fresh launch or manual load/reload; turn it on deliberately.

Once enabled, Autoplay can continue through the match it queued and the normal return to the lobby, preserving the current Full Auto choice. This requires supported teleport settings and loader ordering. OFF, F8, a manual reload or an unverified transition cancels continuation. An expired or invalid continuation record leaves automation OFF; it is not a permanent saved ON setting.

When upgrading from an older loader, rejoin once with automation OFF before enabling the new session. An executor can retain an old queued loader until that first teleport. If Roblox accepts a continuation record but later rejects the write that cancels it, cancellation cannot be guaranteed across that teleport; the session status reports the failure. Leaving the experience clears Roblox's session settings.

The script queues the loader for later teleports when the executor provides a supported teleport queue. For a fresh Roblox launch, configure the executor's own auto-attach and autoexec on **each computer**. Executors without a teleport queue need their autoexec mechanism on each join. Automatic loading is restricted to the supported Chalk It Up place and waits for the game's dependencies.

## Install a local copy and autoexec

Download the repository ZIP and extract it, or clone it:

```sh
git clone https://github.com/BananaMan2006/chalk-assist-deterministic.git
cd chalk-assist-deterministic
```

Run the installer with Python 3. Replace these paths with your executor's actual folders. It uses Python's standard library and does not attach to Roblox.

macOS example:

```sh
python3 install-chalk.py --workspace "$HOME/Opiumware/workspace" --autoexec "$HOME/Opiumware/autoexec"
```

Windows PowerShell example:

```powershell
py -3 install-chalk.py --workspace "C:\path\to\executor\workspace" --autoexec "C:\path\to\executor\autoexec"
```

Add `--dry-run` to inspect the proposed copies. Omit `--autoexec` for manual loading. Keep both executor folders outside the repository. The installer replaces only the bundle and optional loader; it preserves unrelated files and settings.

The default public autoexec loader checks for an update and can fall back to an eligible local copy. Its release and product checks reject older or incompatible downloads. Use `--autoexec-source local` to pin the installed copy. You may also place `chalk-autoexec-public.lua` directly in the executor's autoexec folder.

Load an installed local bundle with:

```lua
loadstring(readfile("chalk-it-up-1v1.lua"))()
```

Installing the loader does not enable gameplay actions. A script cannot attach an executor, create its autoexec folder outside its allowed workspace, or install itself on another laptop.

## Controls

| Control | Purpose |
| --- | --- |
| Drag title bar / minimize | Move or collapse the window |
| Right Shift | Hide or show the window |
| B | Toggle the main assist switch |
| V | Toggle catch assistance |
| Full Auto | Enable authored 1v1 route, coverage and movement decisions |
| Autoplay / mode selector | Queue the chosen supported mode after a completed match |
| Win farm | Walk to the nearest available WR pad between matches |
| Match alerts | Enable or disable match notifications |
| Auto leave | Leave/rejoin when a verified current opponent matches the saved list |
| F8 | Unload and release controls in the current server |

Full Auto, catch assistance, autoplay, WR-pad return and auto-leave start OFF on fresh/manual loads. Verified session continuation restores only Autoplay and the current Full Auto choice. Enabling Full Auto also enables the main assist and catch assistance. Idle protection starts only while an enabled gameplay feature needs it. Turning Full Auto off does not necessarily turn off separately enabled catch assistance; use V or F8 as appropriate.

Full Auto supports **1v1 only**. The autoplay selector may list other modes, but selecting one does not enable team Full Auto. Movement uses the game's normal available movement actions; sprint reservations and collision checks can delay or reject a plan. WR catch assistance plans only a jump or jump-and-dive with sampled geometric evidence of airborne first contact; it does not substitute a grounded catch or dive alone. For a Floater, it targets the earliest robust airborne contact, using jump-and-dive when that produces an earlier useful contact. Bullets retain the downfield contact preference. If no valid airborne window exists, it reports that there is no catch plan and may continue pursuit without issuing a catch action. The current position is checked again before a dive; a delayed jump or changed ball path can cancel that action. In 5.1.1, WR and DB also cancel an unconfirmed jump request once the planned contact has expired, rather than retrying it late; requesting a jump is separate from observing takeoff. Before dispatch, both roles recheck catch geometry from the current pose with takeoff shifted to the actual dispatch time; passing the timing limit alone does not establish reachability. DB still targets the earliest reachable interception. None of these estimates guarantees the server will award the catch. The game can also catch automatically when its own contact conditions are met; the script cannot promise to prevent every native grounded catch.

Full Auto retains a clear, funded middle Floater when a longer middle candidate is blocked; a quarter start is used only with a feasible Floater. Bullet alternatives use the middle stem and cut. Known receiving incompletes, interceptions and breakups discourage the failed pass/side. The defender can use a bounded sprint burst when a fast receiver opens a diagonal gap, retaining the existing 85-start / 70-stop stamina limits for ordinary recovery. A Bullet targeted short of the goal prefers a robust upright jump; a meaningful contested timing advantage can still justify a dive. Floater catches retain the earliest robust airborne preference.

After confirmed possession, a grounded carrier may dive across a nearby goal only when the predicted native dive path crosses it inside the field before the estimated opponent threat. Jukes, spins and trucks still require their own close-threat, native availability, stamina and path checks; spare stamina or an opponent simply standing behind the runner does not force a move.

Catch planning samples ordinary action-delay variation before accepting a scheduled jump. It keeps the current-position checks immediately before dispatch, so a delayed frame or changed position can still cancel an action. The earliest contact means the earliest sampled contact that meets those planning checks, not an exact server guarantee.

A large target-direction change ends the old collision-avoidance hold; turns remain bounded and checked for collisions. Small direction changes keep the existing hold to avoid jitter. This does not guarantee that a delayed or unreachable catch can be recovered.

The auto-leave field accepts exact account usernames separated by commas, semicolons or whitespace; `@` is optional. Press Enter or leave the field to save. Invalid entries preserve the last valid list. Clearing the list disables matching. The game decides whether leaving counts as a forfeit. Saved mode, username and window preferences can persist, but gameplay toggles still reset OFF at startup.

F8 keeps this copy unloaded in the current server. A later join or explicit manual load can load it again, with actions OFF.

## Full Auto route and defense rules

The nominal WR route schedule uses four middle starts followed by one quarter-width start. Its small cycle counter is saved on this computer across sessions; opponent observations and outcomes remain session-only. Middle routes favor a longer walking stem, then a wide left or right cut. The preferred mix uses mostly Floaters with occasional Bullets when the route remains reachable within the timing and stamina budget. Quarter-width starts can cut toward either the same side or the opposite side. This is a deterministic schedule preference, not a random probability or a guaranteed ratio: observed coverage, recent contests, legal route geometry and available stamina can change the choice.

Before accepting a scheduled route, the planner budgets the final sprint through the projected arrival plus an input allowance and a stamina reserve. Setup and the early stem do not spend that sprint budget. A slow or stationary blocker at least four yards up the stem can trigger a clear alternate route family when the estimated walking detour no longer fits. That alternative must retain equal or better estimated defender clearance; ordinary nearby coverage still allows the middle route. During the run, slowing is allowed only when the current distance and remaining cut time leave spare time. Collision avoidance still checks the path; the planned cut deadline keeps advancing. A small early feint is allowed only when its extra travel fits the remaining walking time. Contact delays can still make a pass unreachable. An explicit incomplete discourages the same pass and side on the next choice; repeated incompletes can change the route family. Unknown results do not count as failures.

DB aims to stay just behind the receiver with a small shade toward open field. Tighter lateral following reduces the space lost to a side cut; bounded recovery sprints address a real gap while preserving stamina. Setup still leaves room, and nearby positioning remains flexible. Recent observed deep passes can adjust the authored coverage rule during the session. These are finite rule adjustments, not training or shared knowledge.

## Desktop notifications

The in-game alert and a desktop notification are separate. For the optional macOS floating alert helper, extract `macos-match-alerts-source.zip` and follow [MACOS_ALERTS.md](MACOS_ALERTS.md). The Lua loader does not install or launch that helper. Other operating systems require a compatible desktop notifier.

## Troubleshooting

Check the release badge, the window's status text, and the executor console. Autoexec also writes `ciu_autoload_status.txt` in the executor workspace. If the public download is temporarily unavailable, try the installed local copy. If Full Auto is idle, confirm that it is enabled, the mode is supported, and the game has supplied the current match and character state.

This edition does not read or update neural journals, upload plays for training, or pool learning between laptops. Existing files from a previous installation are not deleted by the installer, but are not a source of learned behavior in this bundle.

For reproducible offline checks, use the commands in [EVALUATION.md](EVALUATION.md). Passing those checks does not establish live catches, wins or compatibility with future game changes.
