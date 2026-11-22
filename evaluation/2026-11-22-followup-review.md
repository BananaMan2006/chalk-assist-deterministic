# November 22 follow-up: opening blockage and missed dives

This is a separate monitoring pass beginning at 11:38:56 a.m. Pacific, after the earlier completed hour. Native awards are counted separately from local contact claims. Forfeit-interrupted throws and match endings are excluded from performance denominators. The outcome ledger specifies the exact cutoff, coverage and whether this pass is complete.

| Version / build | WR catches / resolved throws | DB INT / swat / incomplete / opposing catch | Points conceded | Nonforfeit winning endings |
|---|---:|---|---:|---:|
| 5.1.24 / `98d6fc36be5b` | 15 / 19 | 18 / 1 / 0 / 1 | 2 | 5 |
| 5.1.25 / `819f9f9da5a3` | 4 / 4 | 4 / 0 / 1 / 0 | 0 | 2 |
| 5.1.25 / `84bb5f82ef60` | 8 / 8 | 9 / 3 / 3 / 0 | 0 | 3 |
| 5.1.26 / `09545b3b26f9` | 34 / 37 | 28 / 4 / 2 / 6 | 5 | 12 |
| 5.1.27 / `565c77ca91aa` | 40 / 44 | 38 / 7 / 8 / 1 | 1 | 17 |
| 5.1.28 / `217d14b31332` | 25 / 27 | 22 / 4 / 1 / 3 | 1 | 10 |

Different opponents and exposure lengths prevent a causal improvement or general win-rate claim. A 4–0 score can still contain a receiving failure. The complete [outcome ledger](2026-11-22-followup-results.json) preserves forfeits, exact builds, partial coverage and diagnostics.

This pass is complete: 19:38:56–21:30:00 UTC, with an eight-second result tail. Across all builds, 306 throws and 24 adverse incidents were retained. The final 5.1.28 build recorded 10 nonforfeit wins (nine 4–0, one 4–1), 25 catches from 27 WR throws, and one conceded touchdown. Opponents and exposure changed, so these results do not establish a general win rate.

Live status last updated at 21:29:15 UTC in Lobby. Version 5.1.28 and saved revision 14 settings were verified earlier; current running state could not be confirmed at the end because the game window was unavailable. Collectors are stopped. A roughly seven-second status-snapshot gap during a collector restart is retained in the outcome ledger; event offsets were preserved.

## Changes and verification

- **Opening space:** a legal 1.5-yard start offset under centered pressure, followed by the deep middle cut and the same catch-budget checks. Both 5.1.25 builds used the requested native lineup and caught their first verified shifted Floater. A defender can still follow and obstruct the new start. [Evidence](5.1.25-opening-review.json).
- **Less wasted pursuit:** retain fine checked detours after a catch becomes unreachable. A fixed input improves progress, without proving the entire missed play is rescued. [Evidence](5.1.25-pursuit-review.json).
- **Observed-origin dive check:** discard only a bounded DB aerial dive with no modeled possible contact; retain uncertain and historically successful contacts. Native airborne permission is never overridden. [Evidence](5.1.25-dive-review.json).
- **Stopped coverage restart:** discard an obsolete heading only after a same-body zero-input physical stop and a stationary resumption. Moving reversals and unsafe overlaps retain their checks. [Offline regression](5.1.26-short-stop-review.json), [live trace and limits](5.1.26-live-restart-review.json).

- **Starting-side cue:** 5.1.27 separates centered-pressure starts from the cut cycle, accepting an already-enumerated alternative only at the same deep stem with no worse width, timing, funding, coverage or failure history. It does not force a different cut against a worse observed lane. [Offline route review](5.1.27-route-review.json), [observed native start/cut combinations](5.1.27-live-route-review.json).
- **Turning cost in receiving detours:** 5.1.28 compares both initial passing sides over a bounded short forecast, including actual turn time and current speed. It requires two valid forecasts and a meaningful gain, then retains the chosen side. This corrects the recorded wrong-side progress loss in offline replay without predicting an opponent’s future choices. [Avoidance evidence](5.1.28-avoidance-review.json), [coupled replay and limits](5.1.28-catch-approach-review.json).
- **Missing takeoff evidence:** existing jump-request/retry records now include actual native jump settings, state and nearby numeric body gap after dispatch. This changes neither inputs nor retry limits. A requested jump remains distinct from observed takeoff.

Latest release validation: 564 rule checks, 96 deterministic checks, 75 airborne checks and 36 build/installer/preference checks passed. Local runtime and automatic-loader bytes match the published release; saved revision 14 settings were preserved. The independent [GitHub validation](https://github.com/BananaMan2006/chalk-assist-deterministic/actions/runs/45070407714) passed.

The [5.1.28 native catch evidence](5.1.28-live-catching-review.json) includes both an upright jump and a confirmed jump-and-dive catch. These prove those actions and native awards occurred; they do not establish that the new passing-side choice caused them. The [live comparison record](5.1.28-live-comparison-review.json) distinguishes logged comparisons from alternate-side choices and preserves the existing logger’s visibility limits.

The two later 5.1.28 receiving incompletes remain unresolved. [Opening avoidance](5.1.28-opening-avoidance-review.json), [live overlap recovery](5.1.28-live-avoidance-failures.json), and [rejected early-cut/movement proposals](5.1.28-prethrow-research-review.json) record why the tested alternatives were not installed. A new rule is not treated as a fix merely because it changes the failed play’s inputs.

## Every receiving failure retained

### 5.1.24 revision 1 WR9 — Incomplete

Initially reachable catches became unreachable after repeated passing detours. No jump, dive or local contact claim was observed.

The 5.1.25 pursuit change retains fine-angle candidate search even after no catch is currently reachable. A sampled fixed-state comparison improves forward progress, not proof this play would be caught.

Remaining uncertainty: The separate contributions of initial route loss, subsequent detours and opponent motion are not fully reconstructed.

### 5.1.24 revision 1 WR24 — Incomplete

A 1.015-second frame/callback gap overlapped the opening. Forward progress during the gap was only 0.291 stud; all 17 later catch forecasts were unreachable.

Frame-gap diagnostics identify this interruption; no runtime cure is claimed.

Remaining uncertainty: The reason for engine cadence loss is unknown. The 5.1.25 starting-position shift does not by itself restore a missed second.

### 5.1.24 revision 1 WR25 — Incomplete

Jump and fresh local contact occurred near predicted first touch, followed by native Incomplete.

No incident-specific runtime fix is claimed.

Remaining uncertainty: The client observations do not reveal the server possession-rejection reason.

### 5.1.24 revision 1 WR36 — Incomplete

Opening movement progressed normally, but a later prethrow blocker caused stops and lateral drift. No postthrow catch forecast was reachable.

The 5.1.25 starting-position choice may alter the meeting point but does not directly fix this later obstruction.

Remaining uncertainty: An alternative complete route through the reactive blocker is not yet validated.

### 5.1.26 revision 1 WR8 — Swatted

Jump and fresh local contact occurred, but the native result was Swatted. All 13 recorded reachable forecasts were labeled contested.

No missing-input or contact-discontinuity defect was shown. Candidate 5.1.27 removes a separate start-side/cut-side cue only when an existing same-depth route has no worse modeled coverage, stamina, history or first-contact time. This does not establish the cause of this swat or rescue it.

Remaining uncertainty: The camping gate had no qualifying observations, so the rare Bullet counter was not justified. Replicated pose and predicted arrival do not establish server claim ordering or the opponent’s intent.

### 5.1.26 revision 1 WR34 — Incomplete

The requested shifted start was applied, but repeated passing detours and stops moved the receiver far off the middle stem. All 12 catch forecasts were unreachable.

Four exact recorded avoidance states were replayed. Forcing the opposite passing side left the first three unchanged; the fourth gained only 0.435 stud/s of forward progress. No helper change or reversal of the 21.811-stud deficit is justified. Centered-pressure cut diversity does not change this off-center setup.

Remaining uncertainty: Opponent reactions are not counterfactually simulated. Missing catch actions were consistent with lost reach, not a demonstrated dispatch failure.

### 5.1.26 revision 1 WR74 — Incomplete

Two roughly one-second render/callback and Heartbeat gaps occurred during the Live opening. All 14 catch forecasts were unreachable after the travel deficit.

A finite optimistic early-direct search from the first post-gap state tried 24 movement prefixes across four launch epochs: 0/96 produced a robust airborne endzone catch under native speed/stamina limits. A successful recorded control admitted 18/24 prefixes. Turning and blockers were omitted optimistically; this is not proof that every possible route is impossible. No production recovery change or restoration of the missed travel is justified.

Remaining uncertainty: The engine/cadence interruption cause is unknown. These observations do not prove a slow controller solve or background-only throttling.

### 5.1.27 revision 1 WR10 — Swatted

The existing same-side right-start/right-cut route produced a confirmed jump and fresh local contact, but native possession was Swatted. All 16 recorded reachable forecasts were contested.

No incident-specific runtime fix or successful possession reversal is claimed. The route-diversity change does not establish the cause of this existing same-side swat.

Remaining uncertainty: Client contact, replicated opponent pose and conservative arrival forecasts do not reveal server claim ordering or possession rejection. The rare-Bullet camping gate had no qualifying history.

### 5.1.27 revision 1 WR13 — Swatted

After the right-side swat, route selection switched left. One left route caught, then this left-start/left-cut route produced a jump and local contact but native Swatted.

No missing-action fix or server possession reversal is claimed. Selection did change sides after the earlier right-side failure; this outcome does not justify a blanket delay adjustment.

Remaining uncertainty: No qualifying camping history was present. Client contact and replicated pose cannot establish authoritative claim ordering or explain the native award.

### 5.1.27 revision 1 WR26 — Intercepted

The defender followed the shifted start, then repeated passing detours moved the receiver left before a right-side throw. Six contested catch forecasts appeared briefly, then reach was lost before any scheduled jump.

Exact replay reproduced thirteen avoidance decisions. The new catch encounter preferred a slightly higher instantaneous score even though the other legal side made about one additional stud of checked progress over 250 ms. Candidate 5.1.28 compares both bounded turning paths once at a new WR catch encounter, retains the side lock, and adds no future sprint speed. An approximate full approach replay yielded airborne endzone overlap in three sampled timing cases for the alternate side versus none for the original.

Remaining uncertainty: Clearing an old side alone did not fix the choice; it was selected again from the immediate score. The full approach replay fixes the recorded opponent path and omits server arbitration, collision impulses and some native transitions. It is not proof this interception would be reversed. Live validation of the new branch is still required.

### 5.1.27 revision 1 WR41 — Swatted

A same-side left route produced a confirmed jump and fresh upright local contact, followed by native Swatted. All ten reachable forecasts were contested.

No missing-input defect or incident-specific possession fix is claimed.

Remaining uncertainty: Client overlap does not establish server possession priority. No qualifying camping history justified the rare Bullet counter.

### 5.1.28 revision 1 WR10 — Incomplete

The shifted start was applied, but a head-on defender reversed into the bypass. Large leftward travel and near-body stops occurred before the throw; all fourteen later catch forecasts were unreachable.

Ten exact avoidance decisions were reproduced. Forcing the other side lost sprint at entry, had no usable choice at the next three decisions, and worsened forward travel at a later walking state. No simple side-ranking fix or late-sprint rescue is established. An earlier direct route remains unproven: two actual 200-ms walking prefixes, both side choices, another 200-ms startup allowance and three flight epochs gave zero contacts in twelve offline searches.

Remaining uncertainty: An optimistic straight-prefix search found sampled contacts from elapsed 1.327 s but none from elapsed 2.160 s onward. Those earlier positives did not survive the tested actual-helper prefixes. The private search extended only its offline future-flight horizon from four to seven seconds; production timing stayed unchanged.

### 5.1.28 revision 1 WR25 — Incomplete

A modest stem deficit was followed by a blocked catch approach. Six initially reachable forecasts became unreachable after zero movement and leftward escape despite a rightward target; no jump or dive was dispatched.

Six exact helper decisions were reproduced within 0.00000004 vector error. The first encounter has no alternate-side rescue. A later rightward escape gained about three studs of progress in a 250-ms fixed-motion replay, but reduced minimum body separation from 2.674 to 2.299 studs and from 2.738 to 2.198 in two states. It was rejected as a clearance-preserving fix. No incident-specific rescue is claimed.

Remaining uncertainty: Existing collision checks may leave no safe rightward path at the observed moment. Removing them or forcing sprint has not been justified.

Detailed numeric evidence is in the [WR failure ledger](2026-11-22-followup-wr-failures.json).

## Defensive failures and remaining limits

The pre-update DB Bullet touchdown had no reachable catch forecast. Its earlier stopped reversal is reproduced and corrected by 5.1.26. A later tackle did start, but the opponent changed direction before the predicted contact interval; this is not claimed fixed by the steering change. The historical Floater missed-dive case lost native airborne permission despite physical ascent. Broader schedule searches did not establish a safe rescue, and proximity alone does not prove the cause. [Defensive audit](5.1.26-defensive-failures.json).

The [continued defensive review](5.1.27-defensive-review.json) retains every opposing catch on 5.1.26, including a tackle recovery. Most had confirmed aerial actions and a fresh local contact claim; the native game still awarded the opponent possession. Successful controls overlap their measured jump-height and capsule margins, so a universal timing/height change is not supported. A separate parked jump entered the native Jumping state without lift while another body displaced it; the exact native cause remains unproven. The new response is passive diagnostic evidence, not a claimed cure.

On 5.1.27, [DB27](5.1.27-live-defensive-review.json) had a timely, confirmed jump, followed by native airborne permission becoming false while physical flight continued. The controller discarded the old reach forecast and made a later fresh claim using the shorter native capsule. The opponent received possession; a subsequent tackle prevented a point. This remains an opposing catch, not an interception. A proposed moving approach for the earlier parked-jump failure was [rejected](5.1.27-parked-approach-review.json): its promising early trigger required information unavailable at that time, and later observable triggers did not improve the matched path.

The [5.1.28 defensive review](5.1.28-live-defensive-review.json) preserves a failed first takeoff followed by a confirmed replanned jump and tackle recovery, plus a separate touchdown after a confirmed airborne jump and fresh local contact claim. A third opposing catch followed a permitted grounded DB dive and ended in a tackle that awarded our point. All three remain counted as opposing catches. The traces do not establish a universal timing correction or justify overriding native airborne permission.

Large execution gaps and unaccepted local touch claims remain separate unresolved limits. One new receiving incomplete lost 45.86 studs of required travel after two roughly one-second Live opening gaps with straight input and no avoidance. Controller work stayed below one millisecond, heartbeat data was also stale, and one gap explicitly reported the window focused. [Cadence evidence](2026-11-22-followup-frame-gaps.json) does not establish why the game stalled. All observed automatic WR passes in this pass were Floaters; the rare Bullet counter was not exercised.

The script is deterministic and contains no training or shared learning. Raw client scripts, credentials and player identities are not included in these reports.
