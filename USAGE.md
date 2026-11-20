# Running Chalk Assist 5.1.16

The public repository is [BananaMan2006/chalk-assist-deterministic](https://github.com/BananaMan2006/chalk-assist-deterministic). The ready-to-run file is `chalk-it-up-1v1.lua`.

## Start on a computer

Join Chalk It Up, attach your executor, and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"))()
```

The executor must support HTTP requests and `loadstring`. No GitHub account or token is needed. Verify **5.1.17** in the window's release badge. On a new installation, gameplay automation starts OFF. After you choose settings, later loads and rejoins restore those choices, including ON switches.

Preferences are kept in two alternating, verified local files in the executor workspace: `ciu_deterministic_preferences_v1.a.json` and `ciu_deterministic_preferences_v1.b.json`. A complete copy can recover an interrupted write to the other. If settings cannot be saved or restored, the panel reports the error. File access is required for persistence after Roblox exits. These preferences stay on each computer; they are not sent to GitHub or synchronized across laptops.

Autoplay's separate one-hop session record tracks queue ownership through a match and return to the lobby. It cannot override an explicitly saved OFF choice. F8 stops this instance and its continuation without erasing your saved preferences; a later explicit load or join restores them. Turn the desired switches OFF before exiting if you want them to stay OFF next time.

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

Installing the loader does not select new gameplay settings. When it runs, previously saved ON choices resume. A script cannot attach an executor, create its autoexec folder outside its allowed workspace, or install itself on another laptop.

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

Full Auto, catch assistance, autoplay, WR-pad return and auto-leave start OFF only when there is no saved choice. Subsequent loads restore their saved switches, the master switch, mode, usernames, alerts and window layout. Autoplay and WR-pad repeat remain mutually exclusive. Enabling Full Auto also enables the main assist and catch assistance. Idle protection starts only while an enabled gameplay feature needs it. Turning Full Auto off does not necessarily turn off separately enabled catch assistance; use V or F8 as appropriate.

Full Auto supports **1v1 only**. The autoplay selector may list other modes, but selecting one does not enable team Full Auto. Movement uses the game's normal available movement actions; sprint reservations and collision checks can delay or reject a plan. WR catch assistance plans only a jump or jump-and-dive with sampled geometric evidence of airborne first contact; it does not substitute a grounded catch or dive alone. For a Floater, it targets the earliest robust airborne contact, using jump-and-dive when that produces an earlier useful contact. Bullets retain the downfield contact preference. If no valid airborne window exists, it reports that there is no catch plan and may continue pursuit without issuing a catch action. The current position is checked again before a dive; a delayed jump or changed ball path can cancel that action. In 5.1.1, WR and DB also cancel an unconfirmed jump request once the planned contact has expired, rather than retrying it late; requesting a jump is separate from observing takeoff. Before dispatch, both roles recheck catch geometry from the current pose with takeoff shifted to the actual dispatch time; passing the timing limit alone does not establish reachability. DB still targets the earliest reachable interception. None of these estimates guarantees the server will award the catch. The game can also catch automatically when its own contact conditions are met; the script cannot promise to prevent every native grounded catch.

Full Auto normally submits Floaters with the actual led ball target at least four yards into the end zone. First contact must also be in the end zone; filtering the final intended contact alone is insufficient. One Bullet counter is eligible per opponent session after two completed receiving plays show a sustained deep, stationary defender and the current defender remains deep and slow. It can respond on the next qualified play without waiting for a fixed cycle slot. Only a successful local submission spends the attempt; turning Full Auto off and back on does not restore it. It requires a funded moving jump catch before goal, clear observed run-in space and stamina for a native carrying move. Missing observations or a following defender keep Floaters selected. It selects a deep middle stem with a sharp cut toward either side, budgeting a short early sprint, normal running, any funded late stem burst, and a continuous final sprint to a projected jump catch. The final side cut changes directional input once immediately; subsequent steering corrections remain smooth and collision avoidance still takes priority. When the cut occurs after native launch, a fresh reach check may preserve the middle run briefly; a changed movement budget or lost jump window immediately hands control to catching. An immediate normal airborne catch more than 10 ms earlier than the continued stem also ends that continuation for the throw. Bullet flight support remains for manually thrown passes and opponents' passes. Automatic Bullets are rare checked variations; a failed Floater forecast does not switch the route to a Bullet.

WR dive planning and dispatch require the character to already be inside the end zone. Unknown field geometry or an out-of-bounds origin rejects the dive. A future catch inside the end zone is not enough. The former carrier dive across the goal line is disabled. Jukes, spins and trucks still require their own close-threat, native availability, stamina and path checks.


Catch planning samples ordinary action-delay variation before accepting a scheduled jump. It keeps the current-position checks immediately before dispatch, so a delayed frame or changed position can still cancel an action. The earliest contact means the earliest sampled contact that meets those planning checks, not an exact server guarantee.

A large target-direction change ends the old collision-avoidance hold; turns remain bounded and checked for collisions. Small direction changes keep the existing hold to avoid jitter. This does not guarantee that a delayed or unreachable catch can be recovered.

The auto-leave field accepts exact account usernames separated by commas, semicolons or whitespace; `@` is optional. Press Enter or leave the field to save. Invalid entries preserve the last valid list. Clearing the list disables matching. The game decides whether leaving counts as a forfeit. The list and Auto Leave switch both persist; startup no longer overwrites the switch with OFF.

F8 keeps this copy unloaded in the current server. A later join or explicit manual load can load it again with your saved choices restored.

## Full Auto route and defense rules

WR routes start in the middle, continue as deep as the current native timing and stamina budget can support, and cut sharply left or right. Automatic route selection has no routine Bullet or quarter-start fallback. A rare Bullet variation must retain a funded deep middle cut and airborne catch. Recent outcomes and observed coverage can change the side; the rules remain deterministic and do not train a model. If no funded Floater exists but valid deep route geometry is available, the controller explicitly labels and submits a best-effort Floater with no promised catch. Invalid field geometry still prevents submission.

Before accepting a route, the planner checks its native sanitized geometry, limited stem sprint, final sprint and jump-only catch forecast. It reserves stamina and time for the turn. Collision avoidance still applies. A post-launch middle-stem continuation is rechecked against current position, movement and stamina, and is relinquished permanently for that throw when it no longer fits. Measured timing debt may start a bounded recovery burst before the throw, up to 0.6 seconds per route, only if every remaining planned sprint and the catch reserve remain funded. If the complete requested burst is unaffordable, a smaller burst of at least 0.12 seconds may use the available budget while retaining an extra dispatch allowance. It does not start after launch. A short-field stem can move continuously more slowly to reach its final run at the right time. Upright Floater catches pace ordinary movement through the airborne contact window; they do not stop at an early target and turn back in midair. These are estimates: a jam, delayed event or opponent can still spoil the play.


DB aims to stay just behind the receiver with a small shade toward open field. Tighter lateral following reduces the space lost to a side cut; bounded recovery sprints address a real gap while preserving stamina. Before the throw it reserves 40 stamina; once a live ball arc is observed, it may spend that reserve down to the native action/dispatch floor during interception pursuit. The lower reserve also applies when chasing a verified opposing carrier in the post-catch phase. Unknown holders and prethrow coverage do not unlock it. Setup still leaves room, and nearby positioning remains flexible. Recent observed deep passes can adjust the authored coverage rule during the session. These are finite rule adjustments, not training or shared knowledge.

## Desktop notifications

The in-game alert and a desktop notification are separate. For the optional macOS floating alert helper, extract `macos-match-alerts-source.zip` and follow [MACOS_ALERTS.md](MACOS_ALERTS.md). The Lua loader does not install or launch that helper. Other operating systems require a compatible desktop notifier.

## Troubleshooting

Check the release badge, the window's status text, and the executor console. Autoexec also writes `ciu_autoload_status.txt` in the executor workspace. If the public download is temporarily unavailable, try the installed local copy. If Full Auto is idle, confirm that it is enabled, the mode is supported, and the game has supplied the current match and character state.

This edition does not read or update neural journals, upload plays for training, or pool learning between laptops. Existing files from a previous installation are not deleted by the installer, but are not a source of learned behavior in this bundle.

For reproducible offline checks, use the commands in [EVALUATION.md](EVALUATION.md). Passing those checks does not establish live catches, wins or compatibility with future game changes.
