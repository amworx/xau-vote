# Outcome Recorder Protocol — pre-registered

**Status:** frozen. Written **before** the first outcome is recorded.

**Frozen:** 2026-10-06
**Supersedes:** nothing.
**Authority:** this document, not `docs/mvp-specification.md`, for anything it
covers. Where they disagree, this file wins on outcomes and the spec wins on
everything else.

---

## Why this exists

The product currently reports a verdict and nothing else. That is a scoring
engine with no measurement attached to it, which is indistinguishable from
scoring noise.

Seven independent expert reviews reached the same conclusion: features should
be paused and the **outcome recorder** built first. It is the only work whose
value compounds with time. Everything else is cosmetic until there is an
evidence base.

## The rule this document exists to enforce

**Nothing about the analysis is changed after data starts arriving.**

The engine's thresholds live in `xau_core`'s `Thresholds` class and are copied
verbatim into the recorder's `rule_hash`. If the engine changes, the hash
changes, and new decisions land in a **new** hash cohort. Old cohorts stay
queryable. This is why scoring changes are survivable: they are not hidden, they
are separated.

Anything adjusted *after* seeing results is marked `POST_HOC` in the analysis
and is excluded from the headline number.

---

## 1. What is recorded

Every scan the app performs writes one `scan_decisions` row. Not only trades —
**also every `NO_TRADE`.** That is the single most important property here: the
abstentions have to be in the denominator, or the record is a highlight reel.

Each row stores the decision, the inputs that produced it, and the levels.
**The levels are stored and never published.** That is the entire arrangement
that lets the product withhold prices while still being accountable for its
verdicts.

### Fingerprint

```
rule_hash = sha256(engine_version || canonical_json(thresholds))
```

Computed **server-side** from thresholds compiled into the Edge Function. The
client also computes one and sends it. If they disagree the row is `VOID` with
`void_reason = 'RULE_HASH_MISMATCH'`. A client that tamppered with a score to
look good gets recorded rather than trusted.

---

## 2. The primary metric — fixed now

**Expectancy in R, net of measured spread.**

```
E[R_net] = mean(r_net) over RESOLVED clusters
```

Chosen over win rate because win rate is not comparable across setups with
different target distances. Chosen over profit factor because factor rewards a
single outlier. Expectancy uses every observation equally.

`r_net` is `r_gross` minus the spread cost expressed in R:

```
spread_cost_R = spread_value / risk_distance
r_net = r_gross - spread_cost_R
```

Slippage is **not** modelled, because we cannot currently observe it. This is
recorded as a known optimism. Closing it requires broker-grade data and is on
the roadmap.

### Sample size — pre-computed so nobody moves the goalposts later

Mean R, 95% confidence, two-sided, to detect `+0.15R`:

| Per-trade R volatility | Trades needed |
|---|---|
| σ = 1.0 | **171** |
| σ = 1.5 | **384** |

These are computed, not estimated. They are stated here *before* collection so
that stopping early cannot be reframed as success.

---

## 3. Resolution rule — fixed now

A decision resolves against **closed M15 bars** in `market_bars`.

- **Horizon: 12 closed bars (3 hours)** from the decision bar.
- Walk bars forward in order.
- **Long:** first bar with `high >= tp1` → `TP1`, `r_gross = +1.0`.
  First bar with `low <= stop_loss` → `STOP`, `r_gross = -1.0`.
- **Short:** mirrored.
- If a single bar touches both, the **stop is assumed first.** Intrabar
  sequence is unknowable from OHLC, and the assumption must be the pessimistic
  one.
- Neither within horizon → `TIMEOUT` at the horizon close:
  `r_gross = (close - entry) / risk_distance`, signed for direction. **Counted.
  Not dropped.** Dropping unresolved trades is how a losing system becomes a
  winning one.
- Fewer than 12 closed bars available → stays `PENDING`. Never scored early.

### Clustering — overlapping setups are ONE observation

The methodology is silent on this and it matters enormously: ten signals inside
one gold trend are not ten data points, they are one.

**Rule:** when a decision is recorded, if an existing `PENDING` row exists for
the **same side** with `decided_at` within the last 3 hours, this decision is a
repeat. It inherits that row's `cluster_id` and is marked
`is_repeat = true`. Only `is_repeat = false` rows enter the headline mean.
Repeats are retained and can be analysed separately.

---

## 4. The counterfactual — why abstentions are measurable

`NO_TRADE` rows are recorded, but a `NO_TRADE` has no outcome, so scoring only
trades cannot answer "did the engine's caution help?"

Every `NO_TRADE` therefore also writes a **counterfactual** row with
`is_counterfactual = true`:

- direction: the side the m15 structure was leaning, per the existing engine
- entry: current price at decision
- stop: `1.0 × atr5m` away
- tp1: exactly `1.0R`
- scored by the identical resolution rule

This is pre-registered as the **abstention benchmark**. If the forced-trade
counterfactuals beat the live engine over the same window, the engine's caution
is not earning its cost and that gets reported as a failure, not buried.

---

## 5. Kill criteria — fixed now, in advance

| # | Criterion | Action |
|---|---|---|
| 1 | `E[R_net] <= 0` after ≥171 resolved clusters | **Stop.** Report the failure. |
| 2 | Counterfactual mean beats live mean over the same window | **Stop.** The filters are not earning their keep. |
| 3 | Median spread > `1.0R` of risk distance | **Stop.** The setup is not tradeable. |
| 4 | <60 resolved clusters after 6 months | **Decide explicitly** whether validation is reachable. |
| 5 | `rule_hash` mismatch appears after a code deploy | Halt collection, fix the deploy, do not score across cohorts. |

Publishing a failed test is a requirement of this protocol, not a
discretionary act of transparency.

---

## 6. Access

RLS is enabled with **zero policies**. Only the service role can read or write.
The app cannot read outcomes and cannot insert rows. A client cannot forge an
outcome because it cannot write one, and it cannot read the levels the engine
withheld, because those live only here.

Any future outcome UI goes through a function that returns aggregates, never raw
levels.

---

## 8. As-built corrections (appended 2026-10-06, before any real data)

Four things were wrong in the mechanism as first written. All four were found
by running the recorder end to end against real `market_bars`, not by review, and
all four were fixed while the table was still empty of real decisions. **No real
data had been collected at any point below**, so none of these are `POST_HOC`
changes to a rule; they are corrections to the machinery implementing a rule
that was already fixed.

1. **`NO_TRADE` was not a valid `side`.** The first schema only allowed
   directional sides, so abstentions could not be recorded at all. The row was
   not wrong; the constraint was. Migration `0009`.

2. **An abstention never resolved.** Having no levels, it could not be scored
   against a barrier, so it stayed `PENDING` forever and was re-fetched by every
   settle run indefinitely — a silent full-table scan on every run that looked
   exactly like "no data yet". Abstentions now close at their horizon as
   `outcome = 'ABSTAINED'`, `r_net = 0`, and the summary view counts them
   separately while excluding them from the trade metric. Expectancy per *trade*
   and the *share of decisions declined* are different questions and must not be
   added into one number. Migration `0010`.

3. **A counterfactual could be posted on its own.** That produced a synthetic
   trade with no abstention beside it, which is the orphan case migration
   `0009` exists to prevent — the `CHECK` only checked that a parent key was
   *present*, not that a parent *row existed*. The counterfactual is now accepted
   only as the `counterfactual` field of a `NO_TRADE` record, written
   atomically in the same call, so the orphan is unrepresentable.

4. **`CANONICAL_STOP_CONFIG` was wrong in four of six values.** It had been
   written from memory as `tickSize`/`bufferTicks` with `tp2R` 1.8 and `tp3R`
   2.6; the TS port actually uses `atrBufferMultiple`/`minStopAtr`/`maxStopAtr`
   with `tp2R` 2 and `tp3R` 3. These feed `rule_hash`, so every decision would
   have been fingerprinted against parameters the engine never used. Caught by
   `src/app/test/outcome_recorder_parity_test.dart`, which exists solely to make
   this class of error a test failure rather than a silent split. The fingerprint
   changed as a result, which was free only because the table was empty — the
   hash mechanism working exactly as intended.

### One clarification, not a change

`r_net` can fall **below −1R**. A stopped trade is charged the spread on top of
the full −1R loss rather than assumed to contain it. That was always the intent of
subtracting `spread_cost_R`; it is stated here because ±1R is the mental default
and a −1.5R result will otherwise look like a bug.

### Why the function does not recompute the verdict

The recorder was originally designed to re-run the TS port server-side and store
*its* result, so the client could not forge a verdict. Two obstacles made that
impossible as specified: the deploy bundler does not resolve `../_shared/`, and
shipping a second copy of the engine to work around it would create the exact
drift the design guards against.

What is enforced instead: the rule fingerprint is computed server-side from
parameters compiled into the function, a client reporting different parameters
is `VOID`ed, and settlement reads real prices and never trusts a client value.
A caller can still submit synthetic inputs. That is recorded as limitation 1 in
the function and is **not** fully solved. The honest fix is to give the app
identity so `verify_jwt` can be turned on, and is on the roadmap.

---

## 9. Known limitations, recorded so they are not discovered later

- **Slippage is unmodelled.** Results are optimistic by an unknown amount.
- **Entry uses the recorded price**, not the next bar's open. Fills in a live
  market will differ.
- **Purged history cannot be backtested honestly.** Pre-existing rows have no
  entry/stop/tp and will never be scored. Forward only, from first record.
- **`macro` and `sentiment` are coverage-limited**, so macro-agreeing trades are
  a convenience sample, not a random one.
- The gold-fundamentals layer is currently a **licensing-blocked placeholder**.
  Its removal changes coverage and therefore the hash.