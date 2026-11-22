# One-hour live review — November 22, 2026

The requested observation ran from **05:03:03 to 06:03:03 PST**, with a maximum eight-second result tail for throws already observed. Results are separated by exact running build. Forfeits are excluded from completed-match counts; partial games and failed plays remain in the evidence. This is observational testing against different opponents, not a controlled estimate of improvement.

The hour recorded **171 throws**, **26 completed wins and 1 loss(es)**, and **18 conceded point events**. **14 forfeits** are excluded. A winning game does not erase a missed pass or conceded point.

| Running version | WR catches / throws | DB interceptions | DB swats | Opponent catches | Conceded points, both roles | Completed wins–losses |
|---|---:|---:|---:|---:|---:|---:|
| 5.1.21 | 10 / 16 | 8 | 2 | 6 | 7 | 4–1 |
| 5.1.22 | 15 / 19 | 18 | 1 | 0 | 2 | 7–0 |
| 5.1.23 | 23 / 26 | 15 | 6 | 9 | 7 | 9–0 |
| 5.1.24 | 16 / 17 | 16 | 3 | 3 | 2 | 6–0 |

## Changes tested and installed

- **5.1.22:** compare the actual legal pass target and predicted airborne catch width; retain a funded wide route instead of stopping at a narrower deep route.
- **5.1.23:** begin a shallow checked opening bypass earlier and, against middle pressure, move 0.15 seconds of the existing sprint budget to the opening. This did not eliminate native jams.
- **5.1.24:** require a connected first-contact window through dive tipping, preserve paced motion on the affected defensive Floater jumps, remove a double walking-speed reduction, and record callback timing gaps.

5.1.24 passed 541 rule checks, 90 deterministic checks, 64 airborne checks and 36 build, installer and preference checks. The published runtime and autoexec loader match the laptop copies. The exact build was observed running, with saved Full Auto, 1v1 Autoplay and Auto Leave ON; all seven switches and the selected mode matched saved preferences. [Published checks](https://github.com/BananaMan2006/chalk-assist-deterministic/actions/runs/45029926564) passed.

## Why the recent defensive catches were lost

One missed Floater lost the game’s airborne eligibility about 20 ms before a required dive. The character passed almost directly over the receiver: their horizontal gap shrank to about 1.15 studs while our root was roughly 5–6 studs above theirs. Physical freefall remained true but native airborne reach and dive eligibility became false. Eligibility returned after the contact window. This is consistent with the game treating the other body as support, but the exact engine/server cause was not recorded. The controller did not execute a grounded dive while claiming it was an aerial one.

A later near-body swat succeeded with native airborne eligibility preserved: its dive had begun before the tight overlap. Proximity alone therefore does not establish the cause. A bounded replay of 1,375 nearby lateral/contact choices found no demonstrated earlier robust catch or adequate body clearance for the missed play. That prototype was not installed. A different lost Floater did execute its paced jump and local contact; its actual height was about 0.37 studs below the forecast at contact. Successful controls showed different residuals. A universal height or jump-time adjustment is therefore not supported by these samples.

Local overlap is a catch attempt, not possession. Some misses had a timely jump, dive and positive local overlap, followed by an authoritative opponent Catch or Swatted result. Result positions projected onto the flight describe geometry; they do not reveal server receipt order or its rejection reason.

## Failure coverage and remaining limits

All **14 WR noncatches** and **18 opponent catches on defense** have a case-level review. The defensive ledger includes recovered tackles that conceded no point. Shipped corrections, supported observations and unresolved causes are kept separate.

- Repeated native jams can still consume travel and make the catch unreachable.
- The last receiving incomplete on 5.1.24 began with stalled/backward opening movement and no native jam notice. By throw time, remaining stem distance exceeded current travel capacity by about 19.16 studs; all fourteen catch forecasts were unreachable. Opening obstruction remains unresolved. The initial blocker was about 5.39 studs ahead and closing at 11.98 studs/second. Sprint was rejected by clearance checks, with 75 stamina still available. Every currently searched walking direction failed the opening clearance; an instantaneous backward escape is not yet validated through the actual turn and route deadline.
- A 2.329-second receiving execution/observation gap crossed the jump deadline. Its cause remains unknown; the latest version adds passive timing diagnostics.
- Passing above another character can change native airborne eligibility. No reliable avoidance correction was established in this window.
- Close contested catches remain vulnerable to server outcomes that client logs do not fully explain.
- Every observed WR throw was a Floater. This session does not validate the rare WR Bullet counter.
- Opponents, sample sizes and exposure times differ between releases. Higher observed catch counts do not establish causation, a future win rate, or perfect play.

## Evidence

- [Exact-build results and incident counts](2026-11-22-hour-results.json)
- [Timing, route-width and live execution diagnostics](2026-11-22-hour-diagnostics.json)
- [Every WR failure](2026-11-22-wr-failures.json)
- [Every opposing DB catch](2026-11-22-db-failures.json)
- [Near-body missed-dive and successful-swat comparison](2026-11-22-near-body-catches.json)
- [Connected-contact correction](5.1.24-connected-contact-review.json)
- [Defensive momentum correction](5.1.24-defensive-momentum-review.json)
- [Paced movement correction](5.1.24-paced-movement-review.json)
