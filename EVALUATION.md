# Evaluation scope · 5.1.20

This release continues the authored, deterministic controller. Its checks establish local rule behavior and packaging properties. **They do not demonstrate a live win rate, a winning streak, perfect catching, or improvement through training.** The release has no training system or shared model.

## 5.1.20 scope

A receiving miss showed normal measured travel while a moving opponent stayed within the near-contact band. Sprint was withheld despite two nearby recorded opponent samples admitting the same bounded direction as a strictly separating path at both native speeds. The correction requires measured normal travel, a moving near body, positive separation throughout both forecasts, meaningful ending clearance and protection of every other body and field boundary. It cannot enable unrequested, unfunded, stationary, jammed or approaching sprint. The [moving-escape review](evaluation/5.1.20-moving-escape-review.json) labels the sparse geometry brackets as modeled evidence, not an exact replay or a catch rescue.

A separate upright catch trace exposed early cancellation of a continuous movement plan after a local claim. The bounded continuation retains only the last checked command until the original stop time, for at most 150 ms, with fresh identity, ownership, native motion, reserve, wall and player-clearance checks. It cannot issue another jump, dive, sprint request, target or catch claim. Native results and invalidation revoke it. The [matched claim controls](evaluation/5.1.20-upright-claim-controls.json) include accepted catches with nearly identical margins and deceleration: this is an execution-contract correction, not proof of why the server rejected a particular claim.

Validation passed 532 rule checks, including eight actual claim-lifecycle groups, 53 avoidance checks and 38 controller integration checks, plus 36 build/installer/preferences checks. The 84 Full Auto and 57 airborne checks from the preceding releases cover unchanged policy and geometry modules. The [claim continuation review](evaluation/5.1.20-claim-motion-review.json) documents the scope and limits.

## Bounded 5.1.19 live review

The [five-minute observation](evaluation/5.1.19-live-incidents.json) had three completed 4–0 wins and no runtime errors. WR had six catches, two incompletes and one swatted pass; DB intercepted all six throws. All nine WR plays showed measured early native sprint movement. The new prethrow sprint permission was genuinely exercised, including thirteen retained-sprint observations followed by measured native speed 27. Positive scores do not erase the three receiving failures.

The upright incomplete had a fresh local contact claim and confirmed jump. The no-action incomplete lost reach after a sustained moving overlap. The [swatted pass review](evaluation/5.1.19-swatted-review.json) found every reachable plan marked contested, with the opponent's estimated reachable time preceding our contact. The jump, sprint and local contact occurred; no verified safer reachable alternative or local timing defect was established. Authoritative contest outcomes remain separate from client geometry.

## 5.1.19 scope

A further receiving incomplete occurred after a confirmed jump, dive and fresh local contact claim. That client claim is distinct from the game's Incomplete result; the available trace does not establish the server's rejection reason. Earlier in the same play, the prethrow route controller requested a funded opening sprint, but the avoidance handoff lacked permission to retain sprint through a checked bypass. That was an independent route execution defect, not proof of the later rejection's cause.

The new prethrow permission is restricted to an already-requested, currently funded WR sprint on the current submitted reachable route, with an observed start time and finite future waypoint deadline. Invalid, stale, expired, best-effort and defensive setup inputs remain ineligible. This adds no speed, stamina, reach credit or unchecked path. Regression and live evidence are recorded separately from authoritative possession outcomes. Validation passed 520 rule checks, 84 Full Auto checks and the 20 build checks; the unchanged installer/preferences checks had already passed. The [prethrow review](evaluation/5.1.19-wr-prethrow-review.json) records the failing published-controller regression and the bounded corrected geometry.

## Bounded 5.1.18 live review

The [five-minute window](evaluation/5.1.18-live-incidents.json) contains fifteen resolved throws: WR had seven catches and one incomplete, while DB had six interceptions and one incomplete with no opposing touchdowns. Three completed matches ended 4–0; a partial next game is excluded. All eight observed WR starts used planning stamina 75 and reported native stamina 75. Seven WR plays showed measured opening sprint movement at native speed 27; the incomplete did not. Saved settings matched the runtime and disk journals, with no runtime errors recorded.

The incomplete still had confirmed jump/dive actions and a fresh local contact claim. The [contact comparison](evaluation/5.1.18-wr-contact-comparison.json) includes an accepted same-build diving catch and historical accepted contacts with similar tipping poses or smaller margins. It does not support a universal dive prohibition, larger contact threshold or blind timing change. The server rejection reason remains unresolved. The separate prethrow permission defect is addressed in 5.1.19; no result is rewritten as a catch.

## 5.1.18 scope

Three subsequent receiving incompletes exposed a prethrow route budget mismatch: twenty sampled routes were requested with stamina 100, while their first live movement samples showed 75. The planned opening sprint was then withheld by the real-time reserve check. One failed play also had a native jam; the other lost additional travel to collision avoidance. Neither had a jump, dive or local contact claim after the catch forecasts became unreachable. The available client source does not establish why the initial stamina changes, so the update does not assert a hidden server cost.

Route forecasting now uses a conservative setup allowance and counts recovery of an initial stamina deficit only within the configured regeneration interval and capacity. Middle-stem recovery accounting distinguishes a requested burst from observed native sprint time. This addresses budget and allocation defects; it does not replay server physics or prove that a particular incomplete becomes a catch. A separate sprint-path inconsistency is also corrected: the path forecast previously allowed the character to enter the same near-contact band that forces sprint OFF on the next frame. Opted-in sprint paths now forecast that existing band; ordinary walking avoidance keeps its previous radius. The stronger check retains the actual bounded turn, side lock and stamina gates. Constant-velocity fixtures and a sparse, interpolated incident model are distinct from an exact live replay or proof of an interception. Validation passed 517 rule checks, 83 Full Auto checks, 57 airborne geometry checks and 36 build/installer/preferences checks. The [WR stamina review](evaluation/5.1.18-wr-stamina-review.json) records the native-math replay and its limits; the [DB clearance review](evaluation/5.1.18-db-clearance-review.json) retains both beneficial and adverse modeled crossings. Live observations are recorded separately.

## Continued 5.1.17 live review

The [separate follow-up](evaluation/5.1.17-followup-incidents.json) retained 29 resolved throws: WR had thirteen catches and two incompletes; DB had twelve interceptions, one incomplete and one opponent catch for a touchdown. Five fully observed matches were wins: four at 4–0 and one at 4–1. An initial partial match and three forfeits are excluded. This observation followed the earlier ten-minute window and does not replace or erase it. A [subsequent five-minute window](evaluation/5.1.17-pre18-incidents.json) added six WR catches and one incomplete, plus five DB interceptions, two swats and one defensive incomplete. Two fully observed matches ended 4–0; an initial partial match is excluded. The additional receiving miss remains part of the review.

The sprint permission correction was exercised during active WR pursuit, including four samples that retained sprint without an arrival deadline. It did not rescue the two already-delayed receiving routes. The conceded DB Floater lost reachable forecasts after a close crossing and a required collision detour before the scheduled jump. No already-due feasible jump was omitted. These observations do not justify removing collision checks or guaranteeing possession.

## 5.1.17 scope

A fresh receiving incomplete reproduced an unstable sprint request: while native sprint speed was pending, a reachable jump-and-dive plan became pursuit with no arrival deadline. WR collision avoidance then removed its sprint permission, which could reverse the request before sprint speed arrived. Live WR route intent now retains permission to use a checked sprint during pursuit. No catch deadline or extra reach is invented, and prethrow behavior is unchanged.

Collision bypass selection also compared only walking-safe angles. A slightly wider same-side direction can be safe at sprint speed and make more progress toward the target than the shallow walking-only path. Candidate ranking now uses forward progress at the speed each candidate can safely retain, only when the caller already permits sprint detours. The chosen bounded turn is checked again before movement. Touching, blocked, bounds and stamina gates remain.

Fresh dive rejection diagnostics retain actual position, velocity, timing, direction and motion state for replay. The fresh geometry validators remain unchanged. A separate brief movement stop after a rejected jump remains under investigation; preserving an unchecked heading near an action deadline was not included without sufficient evidence.

Validation passed 515 rule checks, 76 Full Auto checks, 57 airborne geometry checks and 36 Python build/installer/preferences checks. The [receiving incident review](evaluation/5.1.17-wr-incident-review.json) distinguishes the fixed permission loop from collision travel loss and an unresolved native contact result.

Offline regressions establish the specific permission and bypass-selection defects. They do not simulate an entire missed play or establish that server possession would change. Live before/after observations are recorded separately from those tests.

## 5.1.16 scope

A conceded DB Floater exposed an unnecessary dependency between a catch forecast and movement permission. While a sprint request was awaiting observed native speed, a temporarily unreachable plan became pursuit without a catch arrival deadline. That removed the DB sprint-detour permission and could turn sprint OFF again, even where the same actual bounded heading passed both normal-speed and sprint-speed clearance checks. The correction allows checked sprint detours for DB pursuit of an observed live ball, without requiring a currently reachable catch witness. It does not invent an arrival deadline or give a pursuit plan reach credit.

A bounded private reconstruction of one recorded held-heading sample changes sprint OFF to ON without changing direction. The near-synchronous opponent sample and reconstructed previous heading are explicitly recorded as replay assumptions. Seven nearby planner replays reproduce the recorded action, margin and miss distance within numerical tolerance. This demonstrates the permission defect; it does not simulate the whole collision path or establish that the conceded touchdown becomes an interception. Setup phases, missing ball arcs, stamina, touching/blocked states, actual and prospective speed clearance checks and committed-action priorities remain unchanged.

Validation passed 510 rule checks and 26 build/preferences/install checks. The focused independent run passed 120 checks across controller integration, the actual avoidance helper, pending sprint and motion. The new two-frame regression keeps the same safe heading and sprint request at observed normal speed without fabricating a catch deadline; overlap and insufficient budget still release sprint.

## Bounded 5.1.16 live review

The [frozen observation](evaluation/5.1.16-live-incidents.json) retains 34 throws and all eight problem plays. Six explicit completed matches were wins: four at 4–0 and two at 4–1. A separate 1–0 Forfeit has an unknown winner and is excluded. Winning scores do not erase missed catches, defensive incompletes or conceded points, and these observations do not establish a controlled release effect.

The new DB pursuit permission was exercised. Several same-tick unreachable pursuit plans retained a checked sprint on active passing/held-side headings; those balls still remained unreachable, so this verifies the control condition rather than a recovered interception. On a separate conceded Floater, permission was enabled but the prospective sprint path failed the existing 3.75-stud clearance requirement in two reconstructed samples. Walking passed the later check while sprinting failed. No unsupported relaxation was applied.

The first WR incomplete lost reachable forecasts during a required bypass. The initial full-speed heading failed the existing escape checks; reduced movement passed. Later withholding was within the close-contact band. Prethrow travel was already behind the stem budget, and the available records cannot isolate how much delay came from the earlier overlap correction. Another WR breakup followed a confirmed upright jump and fresh local contact with continued local overlap; the authoritative contest result remains distinct from that client claim.

The final WR incomplete had a reproducible fresh-position jump rejection: its recorded timing was inside the allowance, but horizontal position differed by about 0.577 studs; substituting only the expected position at the same time restored validation. A replacement jump-and-dive plan was selected and the jump occurred. A later fresh dive check rejected the attempt after further position drift. The exact rejected-dive snapshot was not logged precisely enough for an exact replay, so this is not evidence of a faulty validator or a reason to force a blind dive. No source change was made from these unresolved cases.

The collector stopped at its fixed deadline. No additional active monitoring is implied after this report; the script's ordinary local event logging is separate.

## Continued 5.1.15 live review

The [bounded observation](evaluation/5.1.15-live-incidents.json) spans about eleven minutes twenty seconds, including roughly 74 seconds of startup backlog before the ten-minute collector. It contained 26 throws and five completed wins: four at 4–0 and one at 4–2. One partial match at 2–0 is excluded from win counts. WR caught all twelve receiving passes for touchdowns; DB recorded nine interceptions, three breakups and two allowed catches for touchdowns across fourteen throws. A rejoin/search gap has no recorded plays and is not counted as games. No runtime errors were recorded. These results are a bounded observation, not a reliability guarantee or a controlled release comparison.

The first conceded touchdown followed a confirmed upright jump and fresh numeric native contact. Local capsule overlap remained positive for another 66.7 ms. Same-build accepted DB Floater contacts include a smaller margin, so a generic margin increase or timing shift is not supported. Server possession ordering remains unknown. The second conceded touchdown lost its normal and then narrow catch witnesses before their jump deadlines; it did not miss an already-due jump. The safe-sprint permission defect described above was demonstrated during that play. Both failures remain in the evaluation despite winning the match.

A [separate continuation](evaluation/5.1.15-followup-incidents.json) retained nineteen further throws with no overlap in events: nine WR catches, eight DB interceptions, one defensive breakup and one allowed Bullet catch for a touchdown. Three fully observed matches ended twice at 4–0 and once at 4–1. Another 4–0 completed the prior window's partial match and is excluded from that fully observed count; a 3–0 Forfeit has an unknown winner. The conceded play had a fresh diving contact claim, followed by a roughly 35-stud post-dive pursuit gap and no recorded close tackle opportunity. There was no sprint-reserve cutoff or runtime error. It remains unresolved.

## 5.1.15 scope

Two jammed receiving misses exposed a clearance bypass in the already-overlapping fallback. After every checked speed fraction on the actual bounded-turn heading failed the existing escape test, it still issued full walking input. Under the helper's observed-velocity model, that chosen motion reduced the predicted minimum separation almost to zero. The correction releases translation while retaining the same bounded heading rotation; a checked escape resumes immediately when available. Already-safe overlap exits are unchanged. No new waiting timer, clearance radius, side preference, sprint permission or turn rate is introduced.

Private constant-velocity integrations of the two recorded states resumed movement after about 150–184 ms. Stationary and mirrored fixtures resumed after about 133–150 ms, then returned to forward movement. These are local geometric checks, not Roblox collision replays: both recorded cases began within native jam range, and a moving opponent can change course. The correction removes an unchecked movement decision; it does not prove that either incomplete becomes a catch.

Validation passed 507 rule checks (including 45 avoidance and 29 controller integration checks), 76 deterministic route/controller checks, and 26 build/preferences/install checks. An independent 27-case stationary-overlap matrix across three frame rates also resumed and cleared in every case. These checks do not establish live catch outcomes.

## Continued 5.1.14 live review

The initial candidate's [frozen observation](evaluation/5.1.14-initial-incidents.json) contained eight completed 4–0 wins, but also four receiving incompletes. All four misses lacked a catch action after reachable forecasts were lost; three had explicit native jam notices and substantial prethrow travel deficits. Two Forfeit endings had unknown winners and were excluded. Those scores were not a stopping condition.

The final candidate's [frozen window](evaluation/5.1.14-final-incidents.json) contains five completed matches: four 4–0 wins and one 3–4 loss. One Forfeit has an unknown winner and is excluded. Across 32 passes, WR had twelve catches and four breakups; DB had nine interceptions, two breakups and five allowed catches. All nine problem plays remain recorded. The loss included several contested receiving claims and allowed defensive catches. A bounded [contact comparison](evaluation/5.1.14-contact-comparison.json) found fresh positive native timestamps in failed callbacks, with ages overlapping accepted catches. Accepted and failed contacts also overlapped in geometric margin, timing and airborne state. This does not support a universal earlier-jump, larger-margin or no-dive fix. It rules out a reset/stale timestamp as the observed explanation, without exposing the server's arbitration reason. Client contact remains distinct from authoritative possession. The loss and every failed play remain in the incident review; opponent changes mean this is not a controlled version comparison.

A fresh in-game preferences check on the exact final 5.1.14 build confirmed all seven switches matched saved values, with Auto Leave, Full Auto and 1v1 Autoplay ON, the saved username list matching its visible field, and no save or restore errors. The GitHub source tree and installed runtime/autoexec were byte-identical, and GitHub checks passed.

## 5.1.14 scope

A demonstrated middle-stem budget allocation defect is corrected: a requested recovery burst was rejected wholesale when only a smaller one was affordable. Recorded eligible snapshots showed unused budget even after reserving all remaining scheduled sprint, final catch travel, the catch reserve and an extra 0.12-second dispatch allowance. The policy now caps the requested burst by that available budget, and the new partial fallback requires observed native speed at least equal to normal running speed. It does not infer that a slowed character can recover normal-speed distance. A bounded private replay found 461 qualifying normal-speed snapshots across the recorded routes; these are independent allocation checks, not a simulated sequence of catches. Existing fully funded choices are unchanged; the 0.6-second total cap, 0.12-second minimum, measured-debt threshold, active-window accounting and prohibition on starting after the throw remain. This recovers usable budget; it does not prove that a jammed receiving miss becomes a catch.

An allowed catch exposed a second defensive stamina cutoff: both the movement policy and assist budget reverted to the 40-stamina setup reserve while chasing the opposing carrier. The correction allows spending down to the normal floor only with a verified opposing holder in RAC/Run. Prethrow coverage, unknown holders and tackle range/cooldown checks remain unchanged. In the audited touchdown the defender was already roughly 36 studs behind after its failed local claim; preserving sprint cannot be claimed to erase that gap.

Local contact records now include the native touch attribute's type, finite numeric value and local clock age. This is observation only: no catch request, packet, native script or claim-cancellation behavior is changed. It can distinguish the inspected native timestamp write from an unrelated attribute change in future evidence. A fallback to an older complete preferences copy is now visible in the panel as well as in status.

A fast outward sideways cut with a small backward component was incorrectly classified as a safe retreat, ending a funded defensive sprint. That branch now recognizes the fast lateral cut while retaining the existing 85-start/70-stop stamina limits, depth band and target positions. Replaying the four recorded frames changes only the two erroneous late OFF requests; all target coordinates remain identical. Pure retreats, slow or inward cuts and small gaps do not unlock a new burst. This avoids unnecessary travel loss; it does not establish that the previously conceded play becomes an interception.

Validation passed 504 rule checks, 76 deterministic route/controller checks, 57 airborne checks and 26 build/preferences/install checks. A separate private native-configuration run passed 167 checks. These do not reproduce server arbitration.

## Continued 5.1.13 live review

The frozen [incident review](evaluation/5.1.13-extended-incidents.json) contains 70 throws and twelve completed wins: eight at 4–0, three at 4–1 and one at 4–2. Three Forfeit endings have unknown winners and are excluded. WR caught 30 of 34 Floaters, with three incompletes and one breakup. DB recorded 25 interceptions, four breakups and seven allowed catches; three were tackled and four became touchdowns. Five opponent points and all eleven problem plays remain in the report. No runtime errors were recorded. These observations do not isolate a release effect or establish reliability.

The updated DB safe-sprint detour permission was exercised during live Floaters, followed by native interceptions. This confirms the branch ran at ordinary native speed; it does not establish a causal win-rate improvement. Receiving jump-and-dive catches also succeeded, but the longer observation still produced failures, so the first two 4–0 results were not a stopping condition.

One jammed WR incomplete was unreachable from the first post-launch snapshot. The observed native jam and detours left a 16.2-stud middle-stem deficit; an exact replay remained unreachable even with the opponent removed. A hypothetical head start restored a forecast, but no observed trajectory achieved it. Another WR incomplete followed an upright airborne local claim with no dive or active avoidance. A successful same-build upright comparison had a smaller edge margin and almost identical takeoff/contact timing. That evidence does not support a blanket dive prohibition, larger margin or earlier jump as the fix. Native possession acceptance remains unresolved. Every further missed catch, allowed catch and point remains in the running local incident review.

## 5.1.13 scope

Saved settings now restore across rejoins, manual reloads and later Roblox launches. The former startup path overwrote Auto Leave with OFF; Autoplay also saved its temporary runtime state. A local two-slot journal now separates the user's durable choices from initialization, queue pauses and unloading. Constructors remain inert until all features exist, then restore once. The journal covers the master switch, assist, Full Auto, Autoplay, WR-pad repeat, Auto Leave, mode, usernames, alerts and window layout. A stale teleport record cannot override a saved OFF choice. Settings remain local to each device. Missing settings start gameplay OFF; an interrupted or unreadable save is reported rather than silently accepted.

A DB pursuing a reachable observed live ball can now keep sprint on a checked detour. Previously only WR catching received that permission, causing unnecessary walking during some defensive bypasses. The caller still enforces stamina, phase, current ball, approach deadline and committed-action gates. The existing helper still checks the actual bounded heading at both speeds and rejects sprint for touching, blocked or unsafe paths. A private actual-pose snapshot replay of incident F002 found two safe sprint witnesses at 41 and 39 stamina where the old permission forced walking. That replay inferred its arrival point from the recorded direction and did not reconstruct every intervening frame, so it does not prove the earlier touchdown would become an interception. New diagnostics record the actual approach point and detour permission for future audits.

Local checks passed **504 rules, 68 deterministic route/controller checks, 57 airborne checks, and 26 build/preferences/install checks**. The preference tests execute the real restore/setter/unload paths, including saved ON/OFF, a torn write, conflicting or corrupt records, mode removal, an existing queue and stale session records. These are offline checks, not native gameplay guarantees.

The laptop naturally loaded the exact 5.1.13 candidate. A read-only in-game check found all seven saved switches equal to their active states and disk readback equal to memory, with Full Auto and 1v1 Autoplay ON and no settings error. Auto Leave was already OFF in the old saved file. After the user explicitly chose ON, a second verified journal revision stored that choice. A later lobby return and match join entered a different server with Auto Leave still ON, all seven saved switches matching runtime, and both the saved username list and visible field matching after normalization. This verifies a natural rejoin; it is distinct from the offline full-runtime restart test.

## Extended 5.1.12 failure audit

Monitoring continued beyond the earlier two 4–0 matches. Every receiving failure, defensive incomplete, allowed catch and opponent point in the audited window is retained individually in the [incident review](evaluation/5.1.12-extended-incidents.json). Winning scores do not remove failures from that inventory. The frozen exact-build window contains 169 throws and 29 explicit completed wins: 21 at 4–0, seven at 4–1 and one at 4–2. Six Forfeit endings have unknown winners and are excluded. WR had 59 catches followed by touchdowns, ten incompletes, five breakups and one interception across 75 Floaters. DB had 64 interceptions, 15 breakups, five incompletes and ten allowed catches, five of which became touchdowns. Nine opponent points and 31 problem plays were reviewed; no runtime errors occurred. This is an observed window, not a reliability guarantee.

The new post-claim traces rule out stopping the native dive as the cause of the inspected WR diving incomplete: the body continued another 2.85 studs after 52 ms and 5.68 studs after 106 ms, remained airborne and diving, and maintained positive local capsule overlap. A defensive diving claim also continued moving. Other accepted dives have overlapping contact margins, tilt and age. The inspected native client sends one Reach request; no rejection reason was exposed by the available result packet. Local contact is not authoritative possession. **These diving failures remain unresolved; this release does not claim to fix their server outcome.**

Other failures had no catch action at all. Several WR forecasts lost reach during necessary blocker avoidance; two were already unreachable at the first post-launch forecast after prethrow travel loss. In the detailed F013 interception replay, the opposite passing side was collision-unsafe or worse, and all jump witnesses disappeared before the scheduled jump. Its route was initially reachable, so forcing a late jump or unsafe side flip is not a supported correction. The chooser's detour-distance allowance is an approximation rather than a commanded path; substituting one hypothetical passing side still passed the forecast and would not explain this case. Other defensive cases distinguish impossible travel, a fresh-position jump rejection, an opponent's earlier contact, and on-time local claims that were not awarded.

## 5.1.12 scope

The DB coverage reserve remains 40 before the throw, but drops to 2 only while the core has an observed ball arc in the Live phase. The existing three-stamina dispatch allowance still applies. Previously the same coverage reserve was applied during an airborne interception attempt, stopping native sprint around 42 stamina. In an exact private replay of one allowed deep Floater, changing only that reserve made all seven early snapshots admit a robust jump-and-dive witness; the first predicted contact was 2.885 seconds after launch. This establishes a reachable forecast, not a reproduced collision path or guaranteed server interception.

The rare camper response no longer waits for step 19 of a 20-route cycle. It can submit one checked Bullet per opponent session after two distinct completed plays confirm sustained deep, stationary defense and the current defender remains deep and slow. Unavailable candidates and failed local submissions do not spend the attempt; toggling OFF does not replenish it. The existing moving airborne catch, carrying-move reserve and observed run-in clearance gates remain. Diagnostics record why the counter is eligible or withheld. This fixes an unnecessarily delayed response, not a demonstrated missed live camper: none of the 31 completed receiving windows audited in the preceding sample met the camping conditions.

The Floater catch priority remains the earliest reachable airborne contact in the end zone, with jump-and-dive considered if it reaches sooner. On each existing postthrow middle-stem refresh, the controller now compares that continuation with an immediate normal airborne catch plan using the same current movement and stamina. If immediate first contact is more than 10 ms earlier, it gives up the stem for that throw and returns to normal catch control. The comparison tolerance avoids reacting to tiny differences between the two forecasts; it is not a requested wait. Risky, grounded or pre-goal contacts cannot trigger this handoff. No extra waiting for theoretical separation was added. A bounded native-configuration route search found no funded sharper alternative to the observed 48.23-degree full-field cut, so this release does not promise a 90-degree route or change geometry without a reachable forecast.

Local validation passed 499 rule checks, 68 deterministic route/controller checks, 57 airborne checks and 16 build/install checks. A separate native-configuration run passed 159 combined route/controller checks. Live validation is recorded separately; these fixtures do not reproduce server decisions.

## Initial 5.1.12 staging observation

Before the additional earliest-stem comparison and post-claim diagnostics, two fully observed matches ended 4–0 and 4–2. DB recorded five interceptions and one breakup, with no allowed touchdown. Actual native sprint continued below the old 43-stamina cutoff in nineteen samples across two DB passes, reaching seven stamina. This verifies the new reserve was actually spent; it does not isolate its effect on the match result.

WR recorded three catches followed by touchdowns and four incompletes. All seven local contact claims were airborne and inside the end zone. The four incompletes followed on-time jump-and-dive actions. A private comparison against three earlier successful diving catches found overlapping dive ages, body tilt and capsule margins, and source-modeled dive positions agreed closely with the observed roots. The native client sends one local Reach request and stops its own contact loop; that request is not authoritative possession. Stopping assist steering does not cancel an already running native dive. These observations do not justify suppressing all dives, inventing retries or claiming a timing fix solves the server rejection. The failures remain unresolved.

The final candidate adds at most four local pose samples during the first 300 ms after a claim while awaiting the result, without changing movement or catch inputs. This makes later body motion observable. No runtime errors occurred in the initial thirteen-throw window; the rare camper Bullet was not exercised.

## Earliest-contact comparison checks

The immediate-versus-continued-stem comparison passed 34 targeted controller checks, including both jump types, an earlier handoff that stays released for the throw, unknown/unsafe contacts, unchanged stamina inputs, the comparison tolerance and refresh cadence. In a separate intermediate live window with the same movement behavior, one match ended 4–0 and another ended 3–0 Forfeit with an unconfirmed winner. Four receiving Floaters were caught for touchdowns, including two jump-and-dive catches. Defense recorded three interceptions and one incomplete. The incomplete had no reachable forecast or action request from the observed pose; it was a deep opposite-side Bullet with insufficient remaining travel time, not a stamina-cutoff or missed-jump event.

The extra comparison cost measured about 46 ms in offline Lua on the private fixture. The final live build recorded ten comparison calls during two valid middle-stem continuations, with a median of 9.08 ms and maximum of 11.92 ms. These run at the existing refresh interval, not on every frame. Runtime/environment differences mean the offline number cannot be treated as a native frame measurement.

## Final 5.1.12 live observation

The final exact build completed two fully observed matches at 4–0. All four WR Floaters produced native catches followed by touchdowns, with airborne local contacts inside the end zone; these were upright jumps, not dives. All four defensive Bullet passes were intercepted. No receiving failures, allowed catches, native jam notices or runtime errors occurred in this bounded eight-throw sample.

The new immediate-versus-stem comparison executed, but no candidate beat continuation by more than the comparison tolerance, so the actual early-release branch remains covered by fixtures rather than a live trigger. Five post-claim pose samples were recorded across three successful plays before authoritative results ended observation. The rare camper Bullet, defensive Floater and lower-stamina DB pursuit were not exercised in this final window; earlier staging evidence for DB Floaters and spending the reserve is kept separate above. The initial four diving incompletes remain unresolved. Two clean matches do not establish perfect catching or a lasting win rate.

## 5.1.11 scope

Catch forecasts now use observed running speed from the first acknowledged but unconfirmed sprint request. The previous 150 ms grace period could predict sprint-speed travel before native speed had increased. Confirmation still restores the sprint-speed forecast; movement penalties remain a separate signal. This removes a demonstrated optimistic witness, but does not recover distance already lost to startup or a blocker.

A rare Bullet counter requires repeated observed deep, stationary defense and current matching coverage, plus its own funded airborne catch and run-in clearance checks. It retains a middle stem and hard side cut, catches before the end zone while continuing to move, and preserves stamina for a native carrying move. It is not a routine Bullet fallback. Timing retains a small dispatch allowance rather than aiming for a literal last-millisecond input.

WR route and catch-specific player avoidance receive the current approach point and arrival deadline so unnecessary side travel and holding can be reduced while collision and field-boundary checks retain priority. A live catch that takes over from an abandoned middle stem can also retain sprint on a checked clear bypass before the old cut deadline; touching, blocked or unsafe headings still reject sprint. In the first intermediate-build miss, logs showed walking detours before that deadline and sprinting detours afterward, consistent with the old gate tying permission to route commitment instead of current catch ownership. None of these checks disables native jams or guarantees an opponent cannot react.

Local 5.1.11 validation passed 495 rule checks, 65 deterministic route/controller checks, 57 airborne checks and 15 build/install checks. A separate native-configuration fixture run passed 156 combined route/controller checks. These remain offline checks; the extracted native fixture is private and is not distributed.

## Limited 5.1.11 live observation

Two fully observed matches ended 4–0. Across eight completed throws, all four WR Floaters had native Catch followed by Touchdown, and all four DB throws were intercepted. No receiving incomplete, opponent catch or runtime error appeared in this bounded sample. The rare camping Bullet did not trigger, so its route and reserve validation remain offline evidence.

Prethrow navigation included checked 5-degree, 10-degree and 25-degree bypasses rather than always starting with the old 35-degree candidate. Larger detours remained necessary around some obstacles. Opening sprint samples showed stamina decreasing from 100 to 84 and 87 on the first two receiving plays. These observations verify that the revised inputs were used; they do not isolate their causal effect on catches. No live postthrow bypass exercised the new safe-sprint handoff permission in this sample, and no claim is made that the native jam effect is removed.

## Extended 5.1.11 observation

The subsequent fixed audit window, including queued records after the initial two-match test, contained thirteen explicit completed matches: eleven 4–0 and two 4–1. Four separate Forfeit endings have unknown winners and are excluded. Across 71 throws, WR recorded 31 catches followed by touchdowns, two incompletes and two breakups; DB recorded 29 interceptions, five breakups, one incomplete and one allowed catch followed by a touchdown. No runtime errors were recorded. Eleven native jam notices occurred across the whole window, but none identified the four failures discussed below. All 35 completed receiving plays were Floaters, and none qualified as repeated endzone camping.

Both WR incompletes lost travel around moving blockers. One initially reachable jump-and-dive forecast disappeared as avoidance redirected movement away from its approach; replacing only the recorded pose with the unblocked forecast restored a witness. A forced opposite-side probe did not provide a safe better path. The other was already unreachable at the first catch solve after prethrow detours and sprint withholding. Neither supports a claim that merely jumping earlier would recover the catch. The two breakups instead had confirmed jumps and airborne local contact inside the end zone before the native Swatted result; these are contested server outcomes. The allowed DB Floater is the reserve case described above. These failures remain part of the evaluation despite the winning match scores.

## 5.1.10 scope

The maximum opening sprint within a deep-middle Floater schedule increases from 0.6 to 0.9 seconds. The total scheduled middle-stem sprint remains capped at two seconds; the later portion shrinks accordingly. The catch budget, conservative regeneration delay, fresh current-stamina checks, airborne contact and endzone gates remain in force. This is an allocation of the existing sprint budget, not extra speed or an instruction to burn stamina whenever the bar is full.

In a private replay of the first two corrected 5.1.9 route inputs, the change retained the same twenty-yard middle stem, 48.23-degree cut, cut deadline and earliest contact. Scheduled progress before the late burst increased by 2.1 studs, and predicted final reserve increased by 7.5 stamina because more of the opening expenditure could recover before the final run. These are forecasts under unchanged inputs, not evidence of greater live separation or a sharper selected route. Live validation is recorded separately when available.

## Limited 5.1.10 local observation (unpublished intermediate build)

The first fully observed match ended 4–1, but WR had two Floater incompletes and one catch followed by a touchdown. DB recorded three interceptions. Neither incomplete dispatched a jump or dive or produced a local catch claim. In the first, repeated avoidance detours and a brief stop consumed travel after an initially reachable forecast. In the second, native speed remained at normal running speed while a sprint request was pending, and the initial witness disappeared before speed rose. These failures differ from the older midair stop/reversal defect. The observation does not establish that the opening-sprint allocation caused either miss, and it does not establish improved receiving from that allocation.

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

The completed bounded corrected-build observation contained six 4–0 matches and two separate native forfeits at 2–0 and 0–0 with no explicit winner. Across 27 completed throws, WR recorded thirteen Floater catches followed by touchdowns, all with observed airborne first local contact inside the end zone. DB recorded thirteen interceptions and the one allowed Floater catch followed by a tackle. Twenty-seven jumps had observed takeoff; both WR dives began inside the end zone. No runtime errors were recorded. Three explicit WR jam notices occurred, and those receiving plays still ended in catches. One postthrow middle continuation moved 17.55 studs over 0.653 seconds before a sharp directional input; most other continuations yielded early. The forfeits are not counted as 4–0 wins or proof of an uninterrupted six-game streak. This bounded test is not a long-run reliability estimate.

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
| UI and packaging | New installs start automation OFF; saved choices restore after construction, learner/transport modules are absent, Lua compiles, and builds are reproducible |
| Loading | Product/release guards, stale download rejection, failed-start fallback, F8 and verified session continuation |
| Installation | Isolated destination checks, dry run, preserved unrelated files and rejection of unsafe destination layouts |

The default route tests use an authored RouteMath approximation. Field bounds are also authored test values. Numeric configuration fixtures exercise rules at explicit values; they are not evidence that the current live game's values match. An optional separately authorized RouteMath fixture can run additional local regressions through `run-chalk-deterministic-tests.py --route-math PATH`; that native source is not distributed here. The retained `chalk-fullplay-selftest.lua` supports those optional regressions.

Offline tests use ordinary Lua and double-precision math. They do not reproduce Luau scheduling, Roblox float rounding, character physics, replication delays, real input dispatch, opponents' choices, or server catch/tackle adjudication. Repeatable script decisions do not make the physical game deterministic. In particular, the game's native Spin action may select its own side; the script checks both candidate paths before requesting it.

## Live evidence still needed

A live check should record the release, mode, which features were enabled, and explicit completed-play and completed-match outcomes. Count unknown or interrupted results separately from losses. For receiving, distinguish catches, incompletes, interceptions and breakups; for defense, record catches allowed, stops and points conceded. Record sprint depletion, early arrival and collision delays when diagnosing a failed play.

Compare changes on sufficiently many similar games and keep manual and automatic play separate. Do not infer a win from a point, a catch from a requested action, or a successful tackle from an animation. Do not pool results from the removed learning system with this release. No estimate for five or ten consecutive wins is supported by the offline fixtures alone.
