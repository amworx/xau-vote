# Events

---

## EVT-20260926-0001

- **id:** EVT-20260926-0001
- **timestamp:** 2026-09-26T23:06:00+03:00
- **mode:** BUILD (project initialization)
- **action:** Initialize xau-radar project
- **summary:** Created project structure per global initialization doctrine: AGENTS.md, docs/, plans/, tasks/, src/, memory/ (5 files). Copied MVP spec from `XAU Radar/` container folder into `docs/mvp-specification.md`. Initialized git repo (branch `main`, repo-local identity `amworx <amworx@local>`), root commit ff86817.
- **result:** success
- **files:** AGENTS.md, docs/mvp-specification.md, memory/*.md, .git/
- **errors:** git commit initially failed (no user identity) → fixed with repo-local `git config user.name/user.email`
- **lessons:** Windows git installs here have no global identity configured — always set repo-local identity before first commit in a new project (see playbooks)
- **tags:** init, project-setup, git

---

## EVT-20260926-0002

- **id:** EVT-20260926-0002
- **timestamp:** 2026-09-26T23:20:00+03:00
- **mode:** PLAN
- **action:** Decompose MVP spec into build plan + task files
- **summary:** Created `plans/2026-09-26_mvp-build-plan.md` (7 phases: Foundations → Consensus Engine → Lifecycle/Confirmation → Data Layer → Supabase Backend → Flutter App → Acceptance) and 7 task files (TASK-00..06) with per-task acceptance criteria and verification commands. Key structural choices: pure-Dart `xau_core` package so engines are fully unit-testable before any cloud/provisioning; 4 explicit user-confirmation gates (G1 flutter create, G2 Supabase provisioning, G3 Gold API, G4 per-source licensing); Flutter app buildable in MOCK_MODE after Phase 3, parallel with backend.
- **result:** success
- **files:** plans/2026-09-26_mvp-build-plan.md, tasks/TASK-00..06 (7 files)
- **errors:** none
- **lessons:** Testability-first ordering (pure logic → mocks → cloud → UI) fits this spec well because the acceptance criteria are logic-heavy and the legal gating is on the IO side
- **tags:** plan, decomposition, mvp

---

## EVT-20260926-0003

- **id:** EVT-20260926-0003
- **timestamp:** 2026-09-26T23:45:00+03:00
- **mode:** BUILD (UI design)
- **action:** Generate 3 Radar-screen design mockups for user selection
- **summary:** Ran ui-ux-pro-max design intelligence (design-system + color + typography + flutter + ux searches) then produced three distinct, working HTML mockups of the Radar screen (spec §3) at 390×844: (1) **Command Deck** — dark navy ops console, Inter + tabular nums, segmented strength meter, R:R band; (2) **Terminal** — OLED black, all-monospace, phosphor-green data + gold signal only, bracket labels, vote block bar; (3) **Aurum** — warm obsidian + champagne gold, serif display numerals, conic strength ring, editorial spacing. All honor spec rules: agreement-not-probability framing, 1H/5M context shown separately, SVG icons only, ≥44px touch targets, reduced-motion guards, zero horizontal overflow (verified via DOM checks in Chrome).
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-1-command-deck.html, mockup-2-terminal.html, mockup-3-aurum.html, preview-*.png (3)
- **errors:** mockup-3 initially had two 8.96px context labels → bumped to 9.6px
- **lessons:** ui-ux-pro-max `--design-system` gave teal/light palette unsuited to trader dark-first expectations — domain-specific judgment (gold-on-dark) overrode generic palette match; kept typography (Inter) and avoid-list guidance
- **tags:** ui, mockups, design-system

---

## EVT-20260926-0004

- **id:** EVT-20260926-0004
- **timestamp:** 2026-09-27T00:05:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Refine chosen direction (Mockup 1) per user critique "best but bad and not unique"
- **summary:** User picked Command Deck structure but criticized craft + distinctiveness. Built mockup-1R: same trusted layout, plus (1) signature RADAR SWEEP dial behind the verdict — rotating conic sweep + source blips plotted on dial (agreeing cluster north/LONG, dissenter south), the app's namesake made visual; (2) bullet-chart strength gauge with labeled WEAK→V.STRONG bands (AAA pattern from charts DB: value always visible as text); (3) craft upgrades: instrument corner ticks, grain overlay, deeper shadows, gradient gold CTA. Verified via DOM checks: 390px, zero overflow, no sub-9px text, blips inside dial, fits one screen. Design-intelligence inputs: bento/swiss style search + chart DB (bullet chart chosen over gauge for space, then hybridized as band+fill).
- **result:** success — awaiting user confirmation of refined direction
- **files:** docs/mockups/mockup-1R-command-deck-refined.html, preview-1R-command-deck-refined.png
- **errors:** none
- **lessons:** "Familiar but generic" critique is best answered by keeping layout and adding ONE ownable signature element rather than redesigning — radar sweep ties directly to brand name
- **tags:** ui, mockups, refinement, radar-sweep

---

## EVT-20260926-0005

- **id:** EVT-20260926-0005
- **timestamp:** 2026-09-27T00:20:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Generate three new clarity-first mockups per user feedback ( crowded layout, focus first-view essentials)
- **summary:** User rejected crowded 1R layout; demanded first-view focus on essentials only (the call, strength, entry/stop). Built three clarity-first variants sharing one strict vertical priority (Zone 1 verdict → Zone 2 strength → Zone 3 three numbers; price demoted to header; R:R band, source dots, context pills removed from first view): (2R) **Clarity** — radar dial + hero verdict baseline; (2A) **Pulse** — sonar pulse rings around verdict core on dark teal-navy; (2B) **Meridian** — zero-chrome editorial, serif verdict on meridian instrument line, ledger numbers, ghost CTA; (2C) **Verdict** — full-bleed tinted verdict field, oversize LONG, source-bar strip, Swiss-poster discipline. All verified: 390px, zero overflow, no sub-9px text after label fixes, screenshots reviewed.
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-2R-clarity.html, mockup-2A-pulse.html, mockup-2B-meridian.html, mockup-2C-verdict.html, preview-2R/2A/2B/2C.png
- **errors:** 2A/2B/2C initially had sub-9px micro-labels → bumped to ≥9.6px, re-verified + re-screenshotted
- **lessons:** clarity-first constraint (one question per zone) produces stronger differentiation than styling alone; all three share information architecture, differ only in personality
- **tags:** ui, mockups, clarity-first

---

## EVT-20260926-0006

- **id:** EVT-20260926-0006
- **timestamp:** 2026-09-27T00:40:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Generate three structurally distinct mockups per user feedback (same layout critique)
- **summary:** User rejected 2R/2A/2B/2C for sharing one vertical-stack layout. Built three mockups sharing ONLY data + spec rules, with different geometry, motion, and composition: (3A) **Orbit** — radial dial composition, verdict core + 270° strength arc + orbiting source blips + satellite level chips, no cards/rows; (3B) **Ticket** — boarding-pass composition, gold direction stub + perforated body + barcode source strip + route header, slide-up + shimmer + bar-grow motion; (3C) **Chart** — layered composition, live canvas price chart (entry band, SL/TP lines, drawing price line) + floating verdict pill overlapping a bottom sheet. Verified: zero overflow, no sub-9px text, no console errors; screenshots visually reviewed. Fixed during review: ticket notches moved from middle to top/bottom edges; chart seed clamped into visible range (TP1 line now visible).
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-3A-orbit.html, mockup-3B-ticket.html, mockup-3C-chart.html, preview-3A/3B/3C.png
- **errors:** two visual defects caught in screenshot review and fixed (notch placement, chart range)
- **lessons:** screenshot review catches what DOM checks cannot (notch position, data-range aesthetics) — always visually inspect canvas/data-driven mockups, never rely on rect checks alone
- **tags:** ui, mockups, distinct-layouts

---

## EVT-20260926-0007

- **id:** EVT-20260926-0007
- **timestamp:** 2026-09-27T01:00:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Generate three Orbit×Chart fusion mockups (Ticket refused)
- **summary:** User refused 3B Ticket; requested three new mockups combining 3A Orbit + 3C Chart. Built: (4A) **Scope** — orbit dial floating over a live full-bleed price-terrain canvas; (4B) **Halo** — 3C chart+sheet layout with the verdict pill replaced by a mini orbit dial (arc + revolving blips) overlapping the boundary; (4C) **Cockpit** — dual instruments: compact orbit dial over a live chart strip carrying the same levels, numbers row below, fits exactly one 844px screen. Verified: zero overflow, no sub-9px text, no JS errors; screenshots reviewed. Fixed: 4C preview timing (added progress probe, captured full draw).
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-4A-scope.html, mockup-4B-halo.html, mockup-4C-cockpit.html, preview-4A/4B/4C.png
- **errors:** none in code; preview timing issue handled via progress probe
- **lessons:** looping canvas animations need a test hook (progress flag) for deterministic screenshot capture
- **tags:** ui, mockups, fusion

---

## EVT-20260926-0008

- **id:** EVT-20260926-0008
- **timestamp:** 2026-09-27T01:20:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Generate three static mockups, all radar/orbit animation removed
- **summary:** User rejected all radar animation. Built three fully static directions (no loops, sweeps, orbits; charts draw once; only the LIVE dot remains): (5A) **Desk** — chart-first trading layout, verdict banner with gold spine, numbers grid; (5B) **Column** — verdict-first editorial, giant LONG, thin chart strip, full ledger with TP1/TP2/TP3 + R:R rows; (5C) **Card** — single floating card (gold top edge) over faint static chart backdrop. Verified: zero overflow, no sub-9px text, screenshots reviewed, 5B fits exactly 844px.
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-5A-desk.html, mockup-5B-column.html, mockup-5C-card.html, preview-5A/5B/5C.png
- **errors:** none
- **lessons:** when the user rejects motion, remove ALL of it rather than softening — static confidence beats animated decoration for this audience
- **tags:** ui, mockups, static

---

## EVT-20260926-0009

- **id:** EVT-20260926-0009
- **timestamp:** 2026-09-27T01:45:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Fresh restart — five radically distinct mockups, no shared skeleton
- **summary:** User judged all prior rounds non-unique. Fresh start, five compositions sharing ONLY data + spec rules: (6A) **Board** — split-flap departure board, flip-tile LONG, dot-leader level rows; (6B) **Rail** — asymmetric split, gold vertical LONG rail + content column with horizontal source tape; (6C) **Bento** — modular tile grid (price/verdict/strength/sources/levels tiles); (6D) **Brief** — analyst signal-feed thread with attachment card; (6E) **Press** — serif broadsheet with masthead, headline, two-column figures, desk byline. Zero dials/orbits/loops anywhere; only one-time entrance settles or fully static. DOM checks passed on all five (zero overflow, no sub-9px text, exact 844px fit). Note: chrome-devtools connection died before screenshots — no preview PNGs this round; HTML files opened directly in user browser instead.
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-6A-board.html, mockup-6B-rail.html, mockup-6C-bento.html, mockup-6D-brief.html, mockup-6E-press.html
- **errors:** devtools timeouts (screenshots + page mgmt) — worked around via Start-Process
- **lessons:** keep browser page count low; devtools becomes unstable past ~8 pages — close stale pages aggressively
- **tags:** ui, mockups, fresh-start

---

## EVT-20260926-0010

- **id:** EVT-20260926-0010
- **timestamp:** 2026-09-27T02:00:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Four Rail-based variants per user pick (6B best) + Material 3 alignment
- **summary:** User picked 6B Rail, asked for more variants. Read mobile-android-design details (M3 nav rail pattern, 48dp targets, tonal surfaces) and built four rail layouts: (7A) **Rail Chart** — same left rail + chart-strip-first column; (7B) **Rail Ledger** — mirrored right rail + full TP1-3/R:R ledger; (7C) **Gauge Rail** — rail itself is the strength meter (82% gold fill + ticks + marker); (7D) **Slim Rail** — 76px M3-style rail (verdict pill + vertical meter) + card column. All static, zero dials/orbits/loops. Verified: zero overflow, no sub-9px text, exact 844px fit; previews visually reviewed. Nav targets bumped to 48px per M3.
- **result:** success — awaiting user selection
- **files:** docs/mockups/mockup-7A-rail-chart.html, mockup-7B-rail-ledger.html, mockup-7C-gauge-rail.html, mockup-7D-slim-rail.html, preview-7A/7B/7C/7D.png
- **errors:** devtools screenshot flakiness (timeouts that still write files); fullPage stitching duplicated content — used viewport captures instead
- **lessons:** prefer viewport screenshots over fullPage in this environment; verify file mtime+size after every timeout
- **tags:** ui, mockups, rail-variants, material3

---

## EVT-20260927-0011

- **id:** EVT-20260927-0011
- **timestamp:** 2026-09-27T02:30:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Apply direction colors, pip distances, position status, copy/share to round-8 mockups
- **summary:** Three user directives applied to all five round-8 mockups: (1) direction in red/green trading colors — LONG verdicts turned green in 8A/8B/8C/8D/8E (SHORT would be red; gold retained for brand/CTA/strength); (2) pip distances on every SL/TP level — SL −160, TP1 +170, TP2 +370, TP3 +620 pips from 4,278 entry ref, entry zone labeled 50-pip zone (D-20260927-003: 1 pip = 0.10); (3) live position status — IN-PROFIT +3 PIPS chip/strip/stamp/route-stop per layout; (4) Copy + Share ghost buttons with clipboard API + execCommand fallback and Web Share API, "Copied ✓" feedback — click-tested working. Verified: zero overflow, no sub-9px text, exact 844px, previews reviewed.
- **result:** success
- **files:** docs/mockups/mockup-8A..8E.html, preview-8A..8E.png, memory/decisions.md (D-003)
- **errors:** none
- **lessons:** pip convention must be a recorded decision — it affects every number in the app, not just mockups
- **tags:** ui, mockups, direction-colors, pips, copy-share

---

## EVT-20260927-0012

- **id:** EVT-20260927-0012
- **timestamp:** 2026-09-27T02:50:00+03:00
- **mode:** BUILD (UI design iteration)
- **action:** Blueprint focus — clarity pass, TF switcher, refresh functionality
- **summary:** Focused on mockup-8B-blueprint per user pick. (1) Clarity: larger verdict (3.2rem), brighter labels, 48px rows, meta triple with color-coded values. (2) Working TF switcher (5M CONFIRM / 15M SIGNAL / 1H CONTEXT): per-TF datasets — 15M LONG 82, 5M SHORT 64 (deliberately dissenting to prove switcher value), 1H BULLISH bias context-only with support/resistance instead of entry/SL and a CONTEXT ONLY flag; CTA on 1H jumps back to 15M; copy text is per-TF. (3) Refresh: header button spins once, content dims, datum price jitters ±0.45, DRAWN timestamp updates — click-tested (4,278.30 → 4,277.85). TF switching re-verified after all edits.
- **result:** success
- **files:** docs/mockups/mockup-8B-blueprint.html, preview-8B-blueprint.png
- **errors:** none
- **lessons:** per-TF datasets make switchers feel real in mockups — static labels would have hidden the 1H-context-only product rule
- **tags:** ui, mockups, blueprint, tf-switcher, refresh

---

## EVT-20260927-0014

- **id:** EVT-20260927-0014
- **timestamp:** 2026-09-27T03:30:00+03:00
- **mode:** BUILD (UI design)
- **action:** Complete Blueprint screen set (Signal, Sources, History, Settings, Events)
- **summary:** User ordered mockup completion before anything else. Built 5 remaining screens in Blueprint language, same 15M LONG fixture throughout: Signal (lifecycle timeline, full TP1-3 + pips + R:R, context badges, working TP selector, copy/share wiring), Sources (5 desk cards with levels/age/reasoning/View Original, independence note), History (stat tiles incl. net pips, 5-row log with outcome pills + pip P&L), Settings (timeframes display, TP radios, signal + event notification toggles incl. always-on invalidation, blackout config), Events (Upcoming/Results/News tabs, JS-tested; blackout + surprise + backdrop content). Verified: zero overflow, no sub-9px text, tabs/TP-selector/copy click-tested, previews reviewed.
- **result:** success — full 7-piece set (Radar, Signal, Sources, History, Settings, Events + Splash) now exists
- **files:** docs/mockups/screen-2..6-*.html + previews
- **errors:** devtools screenshot flakiness again (retry-with-file-check pattern held up)
- **lessons:** fixture consistency across screens (same signal #A482 everywhere) makes the set feel like one app, not six mockups
- **tags:** ui, mockups, full-set, blueprint

---

## EVT-20260927-0015

- **id:** EVT-20260927-0015
- **timestamp:** 2026-09-27T03:45:00+03:00
- **mode:** PLAN
- **action:** Queue next tasks (user leaving, continue tomorrow)
- **summary:** User queued two tasks for next session: (1) per-source toggle switches + target-hit state/percentage on Sources screen (TASK-08); (2) Events filters giving full user control over which events impact signals (TASK-09). Pip-convention question still open (FXPro/Vantage user — asked 1-pip vs 10-pips for a 0.10 move). Session paused by user.
- **result:** queued
- **files:** tasks/TASK-08_source-toggles-hit-stats.md, tasks/TASK-09_events-filters.md
- **errors:** none
- **lessons:** —
- **tags:** plan, queued, next-session

---

## EVT-20260928-0016

- **id:** EVT-20260928-0016
- **timestamp:** 2026-09-28T10:00:00+03:00
- **mode:** BUILD (UI design)
- **action:** TASK-08 done + pip convention set to user-settable default B
- **summary:** (1) Pip decision resolved: user-settable A (0.10) / B (0.01), default B for FXPro/Vantage. Flipped all 9 mockup files to B figures via ordered batch replace (54-line diff, verified zero stragglers); D-003 revised (points stay canonical, pips display-only); Settings gained a DISPLAY · PIP SIZE radio group (B default-checked). (2) TASK-08: Sources screen now has per-card toggle switches + TP1/TP2/TP3 hit-rate bars (per-desk data) + live consensus recompute (independence/strength/band from enabled set; NO CONSENSUS + banner below 2 agreers or on tie/empty) — functionally tested (4/5→2/3→NO→4/5). Preview re-captured and reviewed.
- **result:** success — TASK-08 complete; TASK-09 (events filters) still queued
- **files:** docs/mockups/*.html (pip flip), screen-5-settings.html, screen-3-sources.html, preview-screen-3-sources.png, memory/decisions.md
- **errors:** none
- **lessons:** ordered literal batch replacement across mockups beats per-file edits when a global convention changes — inventory via grep first, verify after
- **tags:** ui, mockups, task-08, pips

---

## EVT-20260928-0017

- **id:** EVT-20260928-0017
- **timestamp:** 2026-09-28T21:10:00+03:00
- **mode:** BUILD (UI design)
- **action:** Compact desk cards + TASK-09 events filters
- **summary:** (1) Sources reworked per feedback: compact cards (desk, TP1% snippet, age, direction, toggle, chevron) with tap/keyboard expand to full details (levels, full hit rates, reasoning, View Original); toggle exempt from expand clicks; recompute + NO CONSENSUS preserved and re-tested. (2) TASK-09: Events gained CCY chips (USD/EUR/GBP), impact segmented (HIGH/HIGH+/ALL), per-event bell mute, and a live guard summary line — functionally tested end-to-end (6 armed → GBP off → HIGH-only → NFP muted ⇒ 3 armed, next blackout correctly moved FRI→WED); added ECB HIGH/EUR, UK CPI MED/GBP, Crude LOW/USD fixtures; Settings gained EVENT FILTERS mirror group. Previews re-captured and reviewed.
- **result:** success — TASK-08 and TASK-09 complete at mockup level
- **files:** screen-3-sources.html, screen-6-events.html, screen-5-settings.html (+previews), tasks/TASK-08/09 (status)
- **errors:** none
- **lessons:** expanding-card pattern keeps the ledger scannable while preserving full detail one tap away — best of both feedback rounds
- **tags:** ui, mockups, task-08, task-09

---

## EVT-20260928-0018

- **id:** EVT-20260928-0018
- **timestamp:** 2026-09-28T21:40:00+03:00
- **mode:** BUILD (UI redesign)
- **action:** Redesign audit applied across Blueprint set
- **summary:** Ran the redesign skill's audit on all 6 Blueprint screens and fixed: (1) font swap — Space Grotesk UI + IBM Plex Mono with system fallbacks, verified active in computed styles; (2) subtle grain overlay on every screen; (3) hover + press (translateY) states on all buttons/nav; (4) meta description, theme-color, and branded SVG favicon everywhere; (5) all nav dead-links cross-wired to real mockup files (verified hrefs); (6) the missing blackout state on Radar — NFP banner with countdown replaces signal card via body class, demo toggle in footer, VIEW EVENTS links to Events screen, screenshot captured. Sentence-case touch on sources hint. Pre-existing interactions (TF switch, refresh, toggles, filters) re-verified intact.
- **result:** success
- **files:** mockup-8B-blueprint.html, screen-2..6-*.html, preview-8B-blackout.png
- **errors:** none
- **lessons:** cascade-order :root override lets one appended block swap fonts app-wide without touching existing rules
- **tags:** ui, redesign, blueprint

---

## EVT-20260928-0019

- **id:** EVT-20260928-0019
- **timestamp:** 2026-09-28T22:00:00+03:00
- **mode:** REVIEW (design-taste audit)
- **action:** Anti-slop sweep across current 7-file set
- **summary:** Applied the transferable rules of the pasted frontend-taste skill as a redesign-preserve pass (product UI, so landing-only rules excluded; drawing-frame labels kept as brand by explicit decision). Mechanical changes: zero em-dashes and zero en-dash separators left in the set (55-line batch swap; ranges now hyphens, e.g. 4,275-4,280); middle dots rationed to max 1 per visible line (5 micro-lines restructured, incl. clipboard copy text); prior pass already covered fonts, dead links, press states, favicon/meta. Re-verified 8B post-sweep: TF switch, refresh spin, copy feedback all green, no console errors.
- **result:** success
- **files:** mockup-8B-blueprint.html, screen-2..6-*.html, splash-candle.html
- **errors:** none
- **lessons:** batch literal replacement + grep verification is the reliable way to enforce character-level style rules across a mockup set
- **tags:** ui, taste-audit, typography

---

## EVT-20260929-0026

- **id:** EVT-20260929-0026
- **timestamp:** 2026-09-29T21:30:00+03:00
- **mode:** BUILD (full MVP implementation)
- **action:** Execute all task phases 0–7 + acceptance (user: loop until finished)
- **summary:** Full build loop executed via 4 workers + master verification. Phases: Worker A (TASK-00 schema SQL + TASK-01 xau_core models/consensus, 51 tests), Worker B (TASK-02 lifecycle + TASK-03 data layer/pipeline, 36+18 tests), master (TASK-04: Deno-TS engine port validated by 7 Node golden tests mirroring Dart expectations, 3 edge functions, RLS migration, backend runbook), Worker C (TASK-05 Flutter Harbor app 5 screens MOCK_MODE, 9 widget tests), Worker D (TASK-07 events/news backend + 6th Events screen, 6 more tests). Fixed mid-loop: removed committed .dart_tool/pubspec.lock (added package + root .gitignore), repaired an accidental mockup overwrite via git checkout. Acceptance (TASK-06): 127/127 green, 4 analyzes clean, `flutter build web` succeeds; evidence doc maps all 23 steps. Pending (need user): G2 Supabase provisioning, device FCM receipt, G3/G4/G5 reviews, license choice. README + fork-readiness done.
- **result:** success — everything automatable is finished and committed; 5 user-side gates remain
- **files:** src/*, supabase/*, README.md, docs/acceptance-run-2026-09-29.md, docs/backend-runbook.md, .gitignore
- **errors:** 1 self-inflicted file overwrite (recovered cleanly); flaky devtools screenshots (established retry pattern)
- **lessons:** verify worker output before committing (caught committed build artifacts); TS port needs golden tests or it WILL drift from Dart
- **tags:** build, mvp, acceptance, workers

## OP-20260929-001 — Full MVP build operation

- **id:** OP-20260929-001
- **timestamp:** 2026-09-29T21:30:00+03:00
- **workflow:** phased MVP build (0→7) + acceptance
- **project:** xau-radar
- **steps:** env check → Worker A (00+01) → verify/commit → Worker B (02+03) → verify/commit → artifact cleanup → Worker C (05) + master TASK-04 in parallel → verify/commit → Worker D (07) → verify/commit → acceptance matrix + web build → README/evidence/memory → commit
- **duration:** single session
- **result:** 127 tests green, app builds, backend code golden-tested, 5 gates pending user
- **lessons:** one worker per phase kept reviews tractable; master-owned verification after every worker is non-negotiable
- **reusable_pattern:** worker-build → master-verify (tests+analyze+spot-read) → commit; batch replacements via ordered literal pairs with grep inventory before/after

---

## EVT-20260928-0020

- **id:** EVT-20260928-0020
- **timestamp:** 2026-09-28T22:20:00+03:00
- **mode:** BUILD (new mockups to taste spec)
- **action:** Generate 3 new Radar directions built natively to the taste skill
- **summary:** Built 9A Stripe (full-bleed verdict band, sharp radius lock, hairline rows), 9B Offset (variance-8 asymmetric grid, staggered rows, right meta rail), 9C Calm (density-2 centered gallery, pill CTA). Pre-flight honored: zero em-dashes (grep-verified), dots max 1/line, one eyebrow max, single-line CTAs (measured), one accent + semantic direction colors, 48px targets, focus rings, tabular numerals, reduced-motion-safe (static), sentence-case footers, tertiary copy/share links instead of duplicate CTAs. Known deviation logged: hand-rolled stroke icons (consistent 1.6 set) instead of Phosphor — acceptable in offline mockups, real build must use a library. Copy/share + nav cross-links working; previews reviewed.
- **result:** success — awaiting user pick
- **files:** docs/mockups/mockup-9A-stripe.html, mockup-9B-offset.html, mockup-9C-calm.html + previews
- **errors:** stale devtools page IDs served a wrong screenshot once — now verifying page identity via DOM before every capture
- **lessons:** never trust a page ID across turns without re-listing; stale pages squat on IDs
- **tags:** ui, mockups, round-9

---

## EVT-20260928-0021

- **id:** EVT-20260928-0021
- **timestamp:** 2026-09-28T22:40:00+03:00
- **mode:** BUILD (new mockup, studio direction)
- **action:** 100% different direction — conversational app paradigm
- **summary:** User rejected the re-skinned 10A (rightly: same skeleton). Deleted it and built 10B Desk Chat instead: no dashboard, no level rows, no bottom nav. The app is a thread with the analyst desk — verdict message with embedded level card, user follow-up, desk answer, suggestion chips, composer. Same fixture data, same green/red semantics, copy flow working. Verified clean, preview reviewed.
- **result:** success — awaiting verdict
- **files:** docs/mockups/mockup-10B-chat.html, preview-10B-chat.png (10A removed)
- **errors:** none
- **lessons:** when the user says "same with minor changes," the fix is a new interaction model, not a new skin
- **tags:** ui, mockups, round-10, chat-paradigm

---

## EVT-20260928-0022

- **id:** EVT-20260928-0022
- **timestamp:** 2026-09-28T23:00:00+03:00
- **mode:** BUILD (new mockup, same behavior new surface)
- **action:** 11A Harbor — new UI skin on unchanged dashboard behavior
- **summary:** User clarified: no behavior change, new layout/fonts/palette/icons/animations. Built 11A Harbor: light cool-mist theme (first light dashboard), cobalt accent, Sora display + Space Mono data, original 1.8-stroke icon set (peak-mark, crosshair, shield-check, flags, radar sweep, person, clock, sliders), asymmetric price/day-move hero, verdict strip, filling strength meter, 2-col level grid. Animations (all motivated, reduced-motion-safe): staggered section rise on load (hierarchy), meter fill (computation feedback), 4s price pulse with green flash (liveness). Verified clean; screenshot caught a live tick mid-flash.
- **result:** success — awaiting verdict
- **files:** docs/mockups/mockup-11A-harbor.html, preview-11A-harbor.png
- **errors:** none
- **lessons:** when the user says "same with minor changes," check the palette first — a hue-family move re-frames everything
- **tags:** ui, mockups, round-11, reskin

---

## EVT-20260928-0023

- **id:** EVT-20260928-0023
- **timestamp:** 2026-09-28T23:20:00+03:00
- **mode:** BUILD (online-expert consultation + implementation)
- **action:** Consult external expert, build 3 advised directions
- **summary:** Per user suggestion, consulted Duck.ai (GPT-5.6 Luna) for 3 fresh Radar-screen directions with a structured brief. Took: depth-bar consensus meter + live ladder marker (12A Depth), dark screen + paper ledger panel + R:R ruler (12B Ledger), 4-zone grid + candle strip + tick illumination (12C Grid). Adapted rather than copied: merged the expert's type picks with our proven stacks where identical, kept our B-default pips/copy-share/nav patterns, fixed the YOU-tag overlap the expert's sketch didn't resolve. Verified clean; previews reviewed.
- **result:** success — awaiting user pick
- **files:** docs/mockups/mockup-12A-depth.html, mockup-12B-ledger.html, mockup-12C-grid.html + previews
- **errors:** none
- **lessons:** external direction + internal product constraints compose well when the brief given to the expert already encodes the constraints
- **tags:** ui, mockups, round-12, expert-consultation

---

## EVT-20260928-0024

- **id:** EVT-20260928-0024
- **timestamp:** 2026-09-28T23:40:00+03:00
- **mode:** BUILD (interactive mockup behaviors)
- **action:** Harbor in action — event state, TP selection, redesigned share
- **summary:** User picked Harbor and asked to see it behave. Added: (1) high-impact event blackout — dark banner with live-ticking countdown replaces verdict/meter/grid/CTA/TP/share while active, NOTIFY ME arms alerts, SIMULATE EVENT demo toggle; caught and fixed two visual bugs via screenshot review (setup controls leaking into blackout, banner text inheriting dark ink on dark bg). (2) Working TP selector (TP1 / TP1+2 / TP1+2+3) that hides cells, widens TP1 solo, and updates the R:R line — tested all modes. (3) Share redesigned from tertiary links to a proper action row: tonal Copy with icon + outlined Share with icon, toast confirmations, Web Share API with copy fallback. All click-tested, zero overflow, committed with both state previews.
- **result:** success
- **files:** mockup-11A-harbor.html, preview-11A-harbor.png, preview-11A-blackout.png
- **errors:** two review-caught defects, both fixed same session
- **lessons:** every new state needs its own screenshot — the banner bug was invisible to DOM checks
- **tags:** ui, mockups, harbor, interactive-states

---

## EVT-20260928-0026

- **id:** EVT-20260928-0026
- **timestamp:** 2026-09-28T23:55:00+03:00
- **mode:** BUILD (design system rollout)
- **action:** Apply Harbor design to all app pages
- **summary:** Rewrote screens 2-6 in the Harbor language (light mist, cobalt accent, Sora + Space Mono, UIcons incl. verified calendar/bell glyphs, 6-item navs everywhere): Signal (lifecycle, full levels, badges, working TP selector, copy/share), Sources (compact expandable cards, toggles, hit bars, live recompute), History (stat tiles, outcome pills), Settings (radios, light toggles, pip selector, event-filter mirror), Events (tabs, currency/impact filters, bells, guard line). All interactions re-tested working; icons verified non-zero; minor size bumps (3 spots); previews re-captured and reviewed.
- **result:** success — one coherent 6-screen Harbor app + splash
- **files:** screen-2..6-*.html + previews
- **errors:** none
- **lessons:** rewriting beats patching when the visual language changes this much — carried-over JS needed only selector-compatible IDs
- **tags:** ui, mockups, harbor-rollout

---

## EVT-20260928-0025

- **id:** EVT-20260928-0025
- **timestamp:** 2026-09-28T23:55:00+03:00
- **mode:** BUILD (icon system swap)
- **action:** Replace all hand SVGs with Flaticon UIcons (Regular Rounded)
- **summary:** Flaticon blocks bots (403) so verified via CDN instead: confirmed v2.6.0 serves the font, then checked all 23 candidate class names against the CSS (22 hit; crosshairs missing, used target instead). Harbor now loads UIcons 2.6.0 and maps 14 icons (logo candlestick, trend-up badge, target, shield-check, 3 flags, copy, share, radar, chart-line-up, layers, clock, settings-sliders). Verified each glyph renders with the uicons font (not tofu) + screenshot review. Attribution comment in file head (free license requires it). Every icon sits beside a text label, so offline viewing degrades gracefully.
- **result:** success
- **files:** mockup-11A-harbor.html, preview-11A-harbor.png
- **errors:** none
- **lessons:** when a site blocks scraping, its CDN often still answers — verify class names against the served CSS, never from memory
- **tags:** ui, icons, flaticon

---

## EVT-20260927-0013

- **id:** EVT-20260927-0013
- **timestamp:** 2026-09-27T03:10:00+03:00
- **mode:** PLAN
- **action:** Design economic calendar + news intelligence feature
- **summary:** User requested event awareness/notifications + news analysis for signal quality. Researched free options: FMP economic calendar free (~250/day) as primary CANDIDATE (Gate G5); Finnhub calendar is paid territory; ForexFactory has no API + scraping stays GATED OFF per licensing rule; GNews free is dev-only (non-commercial + 12h delay); ForexNewsAPI/MarketAux unvetted. Designed `docs/economic-calendar-news.md`: Event Guard blackouts (HIGH USD T−30→T+15, badges not closures), news digest with fixed schema + UNCLEAR fallback, surprise tracking, 5 new notification types, Events screen (6th), radar blackout banner + macro backdrop strip, 3 new tables, 3 new edge functions, provider/licensing table with quota math, 8 new acceptance steps (16–23) incl. never-vote regression. Added plan Phase 7, TASK-07, AGENTS.md rule 9 (context-never-votes). Rollout: guard first (no AI needed), digest last.
- **result:** success — proposed, awaiting user approval + G5 reviews
- **files:** docs/economic-calendar-news.md, tasks/TASK-07_economic-calendar-news.md, plans/2026-09-26_mvp-build-plan.md, AGENTS.md
- **errors:** none
- **lessons:** the licensing gate already in AGENTS.md decided the FF question before it was asked — good rules pay off
- **tags:** plan, economic-calendar, news, feature-design

---

## EVT-20260930-0027

- **id:** EVT-20260930-0027
- **timestamp:** 2026-09-30T00:00:00+03:00
- **mode:** BUILD (redesign)
- **action:** Rebuild the Radar screen + global chrome to the new designer mockup
- **summary:** `docs/mockups/mockup.html` supersedes `mockup-11A-harbor.html` for Radar (structural redesign, not a tweak). Transcribed every size/colour/radius/padding/tracking from the mockup's inline `<style>`. Header: subtitle dropped, brand mark redrawn as a 27px CustomPainter (2px ink border, 8px radius, two cobalt bars), LIVE pill restyled. Price block replaces the IntrinsicHeight two-card hero (32px Space Mono quote, wrap-safe meta row); dark day bar moved below it as a sibling; timeframe segmented display replaces the debug switcher at that position (view-only, 15M stays active per rule 1). Verdict card rebuilt: direction pill with rotated trend arrow, 104px strength meter, 2-column level grid with a full-width highlighted Entry cell and price-distance subs, TP scope pills, agree row with source chips + R:R, copy/share actions. Debug state switcher preserved but demoted to a `DEMO STATE` pill row under the scenario strip, gated on `config.mockMode`. Blackout tall card replaced by a compact guardrail bar (whole bar routes to Events). Global `NavigationBar` replaced with a 72px custom bar (RADAR/SIGNAL/SOURCES/HISTORY/EVENTS/SETTINGS, idle `#8291a7`, no indicator) and the screen order swapped so Events precedes Settings. Signal/Sources/History/Settings/Events screen content untouched; `TargetSelector`/`LevelCell`/`LevelGrid` kept for the Signal screen. 15 neutral tokens added to `theme.dart`.
- **result:** success - `flutter analyze` clean, `flutter test` 20/20 green
- **files:** lib/theme.dart, lib/widgets/harbor_widgets.dart, lib/screens/radar_screen.dart, lib/main.dart, test/radar_test.dart, test/app_test.dart, test/signal_test.dart, test/events_test.dart
- **errors:** (1) removed the `icons.dart` import from radar_screen.dart -> analyzer error, re-added. (2) price meta `Row` overflowed 33px at 390 logical width -> swapped to `Wrap(spacing 13)`, which is identical to the mockup flex row at real font metrics. (3) new test file needed `package:flutter/material.dart` and then `dart:ui` became an unnecessary import. (4) `Clipboard.setData` never completes under the widget-test binding, so the copy toast never appeared -> the snackbar is now raised synchronously and the clipboard write is `unawaited` (also better UX). (5) `signal_test.dart`/`events_test.dart` tapped the nav label `CONFIG`, which the mockup renames to `SETTINGS`, and `events_test.dart` asserted the deleted blackout card copy -> finders updated to the new design rather than reverting it.
- **lessons:** a redesign that renames a shared label or deletes rendered copy invalidates tests outside the "owned" file list - update those finders to the new design, never bend the design back. Golden screenshots at 390px are worth generating once during a Flutter redesign even though custom fonts do not load under `flutter test` (fallback metrics are wider, so they surface real overflows).
- **tags:** ui, redesign, radar, mockup, harbor, chrome

### Decisions recorded here
- Day bar `RANGE` renders `—`: the MVP `DisplaySignal` carries no session high/low, and rule 2 forbids inventing one. `DayMoveBar` takes an optional `range` for when the live feed supplies it.
- Price meta `Updated` reads the device clock (`clockLabel()`) instead of freezing the mockup's literal `22:58`.
- Quote badge shows the day move as a percentage of the implied open (`price - dayMove`); a negative day is coloured `harborShort` rather than the mockup's unconditional green.
- Level subs are price distances (e.g. `-15.50`), not pip counts.
- COPY LEVELS and SHARE both write the same summary to the clipboard and toast: the MVP has no platform share channel and `share_plus` is off-limits.
- Radar gets its own `TargetScopePills` (TP1/TP2/TP3) rather than reusing `TargetSelector`, so the Signal screen and its `SegmentedButton` assertions are untouched; both read/write the same `AppState.targets`.
- The timeframe switcher carries no gesture handler on purpose: 5M/1H taps must never change consensus (rule 1).

---

## EVT-20261001-0031

- **id:** EVT-20261001-0031
- **timestamp:** 2026-10-01T00:00:00+03:00
- **mode:** BUILD (fix defects)
- **action:** Implement the pip-size A/B setting (D-20260927-003) and fix three wrapping / consistency defects
- **summary:** Four targeted defects. (1) **Pip convention** - `PipConvention {a,b}` with `pipFactor` (A=10, B=100) in `display_models.dart`; `pipsTo(target, entryMid, {required int pipFactor})` keeps the original truncate-then-scale math; `AppState` gained `_pipConvention = PipConvention.b` + getter + notifying setter; Settings gained a DISPLAY group of `HarborPill` selectors labelled `A - 0.10` / `B - 0.01` with the subtitle "Display unit only - prices and levels never change". Every pip readout is now derived at render time: Signal (TP row, stop sub-line, TP sub-lines, entry zone, position badge, position strip, clipboard summary) and History (per-row outcome, NET PIPS stat, caption). Fixtures store POINTS, not pip strings: `DisplayHistoryEntry.pipsPoints`, `MockFixtures.historyNetPipsPoints`, `MockFixtures.openPositionPoints`. (2) **Signal stop sub-line** - dropped the `pts` unit from `-1600 pips - risk 15.5 pts`; a half-grid cell is ~135px at 390px. (3) **History detail line** - `_tighten` now collapses `' - '` to `'.'` (was `' -'`, which only saved one char per break and still wrapped the widest row), and the no-consensus row's prose was shortened. (4) **Settings** - header subtitle was already `SETTINGS`; the OFF switch thumb is now a constant white so the track alone carries on/off, and the always-on invalidation alert dims as a GREEN track rather than an OFF-pale one.
- **result:** success - `flutter analyze` clean, `flutter test` 29/29 green, no RenderFlex overflow and no one-line wrap at 390px on any of the six tabs
- **files:** lib/models/display_models.dart, lib/state/app_state.dart, lib/data/mock_fixtures.dart, lib/screens/settings_screen.dart, lib/screens/sources_screen.dart, lib/screens/history_screen.dart, test/pip_convention_test.dart
- **errors:** (1) Grepping for pip call sites missed the **Sources** screen, which carried a hardcoded `'4,262 - -1600p'` string per desk - a fifth call site the brief did not list. Fixed by adding `DisplaySource.stopPoints` and deriving the figure; desk D quotes a bare level so its `stopPoints` stays null and the row invents nothing. (2) A first layout probe used `actualHeight > preferredLineHeight + 0.5` and reported 100+ false wraps - the laid-out height differs from the preferred line height by ~2px of rounding. A real wrap nearly doubles the height, so the threshold is `1.5x`. (3) The first `_tighten` attempt (`' - '` -> `' -'`) fixed only the cited SHORT row; the 47-char TP3 row and the 51-char no-consensus row still wrapped, which is what drove the stronger rule and the prose trim. (4) `const f = PipConvention.b.pipFactor` fails to compile - extension getters are not constant expressions.
- **lessons:** a "render-time derived" refactor is only complete once EVERY surface is grepped for the literal, not just the sites the brief names - a preformatted string in a fixture renders exactly like a derived one. Measure a wrap by the ratio of laid-out height to preferred line height, never by an absolute pixel delta, or font rounding drowns the signal. To prove a display-scale refactor is behaviour-preserving, keep a verbatim copy of the OLD function in the test and assert new-default == old for every fixture level; that turns "I think the numbers did not move" into a regression guard.
- **tags:** pip-convention, D-20260927-003, settings, layout, 390px, wrap, display

---

## EVT-20260929-0032

- **id:** EVT-20260929-0032
- **timestamp:** 2026-09-29T23:10:00+03:00
- **mode:** MEMORY / BUILD
- **action:** Gate G2 first contact + full project rename to XV (XAU-Vote)
- **summary:** Supabase project provisioned far enough to apply migrations: CLI is not authed against the account, so migrations went over a direct pooler connection. Two self-inflicted errors cost time and are now the durable lesson: (1) the pooler username is `postgres.<project-ref>`, NOT the password — putting the password there produced a misleading `tenant/user not found`; (2) region must be probed, not guessed (`eu-central-1` assumed, project was actually `ap-northeast-1`). Migrations 0001/0002/0003 applied and verified (8 tables over PostgREST, anon insert correctly rejected by RLS). Function deploys/secrets/schedules still blocked on Management API auth. Then renamed the project: folder, Dart package, Android id, labels, titles, in-app wordmark + brand mark (candlestick bars -> cobalt XV monogram), 21 generated launcher/web icons, MIT LICENSE, and all current-facing docs. Historical artifacts left untouched on purpose (applied migrations, memory log, archived mockups, original spec).
- **result:** success — 29/29 app tests green after rename, analyze clean; migrations live; icon + brand shipped
- **files:** whole repo (rename), tools/make_icons.py, LICENSE, docs/backend-runbook.md
- **errors:** Move-Item failed on .git (shell CWD lock) leaving an empty orphan dir; PowerShell Set-Content wrote ANSI and mangled one em-dash in main.dart (caught by diff audit, fixed)
- **lessons:** (1) Never write source files with PowerShell Set-Content — it defaults to ANSI and silently corrupts Unicode; use [IO.File]::WriteAllText with UTF8Encoding(False) or the edit tool, then audit with git diff. (2) Supabase pooler username is the project ref, not the password. (3) Probe the region, never guess it. (4) Run git commands from OUTSIDE the folder being moved.
- **tags:** g2, supabase, rename, xv, icons, licensing, encoding

---

## EVT-20261004-0033

- **id:** EVT-20261004-0033
- **timestamp:** 2026-10-04T00:20:00+03:00
- **mode:** MEMORY / BUILD
- **action:** Phone-reported bug batch, part 1 of 2 (paused by user)
- **summary:** User tested the release APK on device RFCWA0BJT9F and reported 7 UI bugs plus an icon-quality request and a TP1-only default. Fixed 5 of them: the timeframe switcher was inert *by design* (no tap handler at all) and is now stateful; a trade setup is now withheld while the market is shut; the Sources page hardcoded an empty list in live mode and now reads real contributing rows; the countdown rendered a 6-day release as 141:33:44 and now scales MM:SS / HH:MM:SS / 6d 03:20 with a drift-free tick; the status pill is now the Uiverse pulse (Yaya12085, MIT). Also set the target scope default to TP1.
- **result:** partial success - analyze clean on both packages, 251 core tests green, 102/110 app tests green, 8 tests deliberately left red
- **files:** src/app/lib/models/display_models.dart, src/app/lib/widgets/harbor_widgets.dart, src/app/lib/screens/{radar,sources,signal}_screen.dart, src/app/lib/data/{live_data,live_repository}.dart, src/app/lib/state/app_state.dart, src/app/test/*.dart, plans/2026-10-03_phone-bugfix-handoff.md
- **errors:** (1) Wrote test files with PowerShell Set-Content despite EVT-20260929-0032 explicitly forbidding it; it re-added duplicate imports and broke pip_convention_test.dart, forcing a revert. (2) PulseDot used a late final AnimationController, so dispose() could construct it and throw "Looking up a deactivated widget's ancestor is unsafe". (3) Offline tests started failing at the weekend because the session gate read the real calendar. (4) A PowerShell -replace over a whole test file silently rewrote unrelated strings.
- **lessons:** (1) Set-Content corrupts Dart source; use the edit tool or [IO.File]::WriteAllText with UTF8Encoding(False). This was already recorded and was still violated - treat it as a hard rule. (2) A late final field initialiser is lazy: if the field is only read in dispose(), it constructs there, when the element is deactivated and Ticker creation throws. Make it nullable and eager. (3) Any widget that reads the wall clock makes its tests calendar-dependent; give it an explicit @visibleForTesting override instead of letting the suite pass midweek and fail at the weekend. (4) Offline/fixture builds should not gate UI on real-world state, or a preview is silently blanked on weekends.
- **tags:** ui, radar, sources, events, countdown, session-gate, uiverse, pulse, targets, testing, encoding

---

## EVT-20261004-0034

- **id:** EVT-20261004-0034
- **timestamp:** 2026-10-04T02:40:00+03:00
- **mode:** MEMORY / BUILD
- **action:** Event outlook engine, events list redesign, alert-bell semantics, contextual notification permission, verified keystore backup
- **summary:** Finished the paused bug batch and the follow-up requests. Built EventOutlookEngine in xau_core (16 tests): per-release expectation for gold with NO PREDICTION as a first-class outcome (no forecast / no previous / coincident high-impact releases / no USD linkage / not yet released). Redesigned the events row: impact colour bar, country flag beside the ISO code, ACTUAL/FORECAST/PREV, outlook line. Flipped the bell from mute-by-default to enable-by-default, and stopped silencing from changing the blackout card (the "first row swaps" behaviour). Notification permission now requested in context from Settings rather than at cold launch, with POST_NOTIFICATIONS and the FCM service declared. Encrypted the release keystore with gpg and verified it restores byte-identically.
- **result:** success - 267 core tests, 110 app tests, analyze clean on both packages, release APK signed and launched on device showing MARKET CLOSED with levels withheld
- **files:** src/xau_core/lib/analysis/event_outlook.dart, src/xau_core/test/event_outlook_test.dart, src/app/lib/{models/display_models.dart,data/live_repository.dart,screens/events_screen.dart,screens/settings_screen.dart,services/notification_service.dart,services/update_service.dart,widgets/harbor_widgets.dart}, src/app/android/app/src/main/AndroidManifest.xml, plans/2026-10-03_phone-bugfix-handoff.md, RECOVERY.md (outside repo)
- **errors:** (1) PulseDot animated in offline previews, so every pumpAndSettle in the suite timed out - an endlessly repeating animation keeps the frame scheduler busy. (2) UpdateService.cancel closed the same IOSink as the download loop, making the cancel test order-dependent and intermittently red. (3) ReleaseInput could not be const because the engine mutates others; and my first version used a late final clock plus an identity extension over a static Map, both replaced with an injectable nullable clock and an explicit id field. (4) firebase_messaging 16 removed isGranted(); the answer now comes from getNotificationSettings().authorizationStatus. (5) Android channel creation needed firebase_messaging_platform_interface, so it was dropped rather than adding a dependency.
- **lessons:** (1) A widget that repeats an animation forever will hang any test using pumpAndSettle - gate decorative motion on real state, not on build mode alone. (2) Two code paths touching the same resource need one owner: cancel now awaits the download rather than racing it. (3) Never fake a data feed to satisfy a UI field. The empty FCAST/PREV the trader reported is 6 fixture rows with null actual/forecast/previous, and no licensed calendar provider is specified; the outlook engine returns NO PREDICTION rather than inventing figures. (4) Ask for a permission when the user expresses the want (switching an alert on), never at cold launch - a startup prompt is the surest way to earn a permanent denial, and only ask if the app can honour it. (5) An encrypted backup nobody has decrypted is a guess. Always verify by restoring and comparing a digest before telling anyone it is safe. (6) An icon font swap is a build-tooling project, not an asset copy; do not half-migrate it.
- **tags:** event-outlook, events, alerts, notification-permission, keystore, backup, gpg, icons-streamline, testing, race-condition
