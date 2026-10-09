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

---

## OP-20261005-0002 - Treasury + CFTC sentiment-layer vertical slice

- **id:** OP-20261005-0002
- **timestamp:** 2026-10-05T19:00Z .. 2026-10-05T19:20Z
- **workflow:** BUILD + RESEARCH + VERIFY
- **project:** xau-vote
- **objective:** implement two of the four A85.1 sentiment layers (market_implied 20%, positioning 25%) end to end on the methodology, in a Supabase Edge Function.
- **steps:**
  1. Validated both sources. Treasury real-yield CSV: 200, public, no key. CFTC weekly .txt: 200, no header line, fixed columns -> mapped by hand against the yearly archive header.
  2. Discovered A81.6 needs a 156-week percentile, so a single week is not enough -> pulled three years of yearly zips and built the series.
  3. Extracted scoring into `supabase/functions/_shared/sentiment.ts` (pure, no Deno globals) so it is unit testable with `node`, matching `_shared/engine.ts`.
  4. Wrote `sentiment_test.ts` with fixtures taken from the LIVE publications, not invented numbers.
  5. Created `sentiment_layers` (migration 0004) and deployed `sentiment-layers` v1.
  6. First live run: Treasury wrote, COT 403 -> function correctly reported `positioning unavailable` and `ok:false` instead of scoring 0.
  7. Probed CFTC endpoints: `www.cftc.gov` is behind a Cloudflare challenge from Supabase egress (403, UA spoofing does not help); `publicreporting.cftc.gov` Socrata returns 200. Moved to dataset `72hh-3qpy` (Futures Only), cross-checked against the .txt.
  8. Found A85.3's bands contradict each other; resolved narrow-band-wins and recorded it (D-004).
  9. Found a real timezone bug: `new Date('10/02/2026')` is local midnight, so the Treasury reading landed a day early east of UTC. Added `parseTreasuryDate`.
  10. Scheduled cron, then found `xv_invoke_function`'s allowlist did not contain the new function -> nightly runs would have raised while cron looked healthy. Fixed (0005, D-006).
  11. Found `updated_at` had no trigger, so it could not verify anything. Fixed (0006).
  12. Measured per-source latency: Treasury ~18s/request, CFTC 0.7s. Cut runtime 40s -> 23s by fetching one year with a conditional fallback.
  13. Verified the cron path end to end twice via `xv_invoke_function`; all four rows advanced `updated_at`.
  14. Wired the app: `SentimentLayers` model + `LiveRepository.sentimentLayers()`, with macro alignment coverage-gated at 50% because `macro < 0` vetoes a trade.
  15. Deleted the diagnostic function.
- **duration:** ~35 min of tool time
- **result:** all four layers persisted with real values; 24/24 Node tests, 20/20 Dart model tests, 177/177 app tests, `flutter analyze` clean.
- **lessons:**
  - A CFTC weekly report has NO header row; the yearly archives do. Parse archives by column name, never positionally.
  - `www.cftc.gov` is unreadable from Supabase; its Socrata API is the same data, faster, and reaches further back.
  - Adding a cron job proves nothing. Confirm the dispatcher can name the function, and have a timestamp column that actually moves before using it to verify.
  - A spec whose band list overlaps will silently decide verdicts. Resolve it explicitly and record which way.
  - Date-only strings parsed with `new Date(string)` inherit the runtime timezone. Parse the parts.
- **reusable pattern:** scheduled ingestion on Supabase = allowlist entry + pg_net-visible side effect + a trigger-maintained `updated_at` + a failure path that writes an explicit unavailable row. All three were missing at first.
- **files:** supabase/functions/sentiment-layers/index.ts, supabase/functions/_shared/sentiment.ts, supabase/functions/_shared/sentiment_test.ts, supabase/migrations/0004-0006, src/app/lib/models/sentiment_layers.dart, src/app/lib/data/live_repository.dart, src/app/test/sentiment_layers_test.dart, src/app/test/live_mode_test.dart
- **errors:** CFTC 403 (worked around via Socrata); Edge Function bundle failure twice (entrypoint must keep its function directory so `../_shared/...` resolves); test fixtures I fabricated failed and were replaced with real data; a duplicate `main()` in live_mode_test.dart.
- **open:** `net.http_timeout` still shorter than the run, so a scheduled failure would be invisible in `net._http_response` (needs an owner-level role). Policy (35) and WGC (20) layers not built. The app does not yet assemble `ConfluenceInput` from these states. pg_net keeps 3 pending rows. Service-role key pasted in chat still needs rotation.

---

## EVT-20261005-0018 - Side-aware macro overlay + policy layer (35%)

- **id:** EVT-20261005-0018
- **timestamp:** 2026-10-05T19:25Z .. 2026-10-05T20:35Z
- **mode:** REVIEW + BUILD
- **action:** Found and fixed a direction-blind macro/sentiment overlay, then built the policy layer.
- **summary:**
  1. While wiring live macro data in, noticed `confluence.dart` step 13 was the only side-unaware check in the scorer. `macro < 0` vetoed longs AND shorts; a bullish macro credited longs and did nothing for shorts. Reachable only because real data had just been wired. Fixed by flipping alignment for shorts; added `macroAgrees` / `sentimentAgrees` to the result so the UI can still show the layer's true direction. +7 tests.
  2. Built policy (35%) from the FOMC statement's own decision sentence, per A85.2. Latest + previous statement so the target-rate change has a baseline.
  3. Live result: 2026-09-16 was a 25bp HIKE to 3.75-4.00%, no dissents. raw -2, effective -1.03 at 20 days via A85.2's exp(-days/30). Previous (2026-07-29) was a hold at 3.50-3.75% WITH a dissent, giving target_change_bp = +25.
  4. Rejected FRED (times out from two hosts) and the SEP projections (PDF only). A85.2 items 4-7 recorded as `sep_projection: null` with a reason.
  5. Did not implement the hawkish/dovish bands on an unchanged decision - that needs free-text classification, and A85.2's own critical rule says statements are inputs not truth. Holds score 0 and say so.
- **result:** macro coverage 27% -> 73%, so the D-004 alignment gate clears on merit rather than being weakened. Live macro alignment now -1, sentiment -1.
- **errors:** the first policy write failed on `smallint` receiving -1.03; widened the column to numeric(4,2). Two of my own test assertions had wrong arithmetic (exp decay) and one used `reduce` while the parser only accepted `decrease`. My dissent parser truncated "Beth M. Hammack" to "Beth" because a middle initial is itself a period.
- **lessons:**
  - Dead code hides bugs. The overlay was unreachable only because nothing fed it; wiring real data is what made the defect observable.
  - A "score" column must be typed for the value the spec produces. A85.2's decay is fractional, so smallint was wrong from the start.
  - Regex over prose breaks on abbreviations. Names with middle initials need the sentence end found by shape, not by the next period.
  - Widening a gate is worse than satisfying it. Building policy cleared the coverage threshold legitimately; lowering the threshold would have been a way to make a thin read look authoritative.
- **files:** src/xau_core/lib/analysis/confluence.dart, src/xau_core/test/confluence_test.dart, supabase/functions/_shared/policy.ts, supabase/functions/_shared/policy_test.ts, supabase/functions/sentiment-layers/index.ts, supabase/migrations/0007_sentiment_layers_score_numeric.sql, src/app/lib/models/sentiment_layers.dart, src/app/test/sentiment_layers_test.dart
- **tags:** confluence, side-awareness, policy, fomc, methodology, coverage-gate

---

## EVT-20261005-0019 - Fix the updater install permission (the user hit this on hardware)

- **id:** EVT-20261005-0019
- **timestamp:** 2026-10-05T21:00Z .. 2026-10-05T21:40Z
- **mode:** BUILD
- **action:** Made the app request the Android install permission instead of only naming it.
- **result:** Real grant check via `canRequestPackageInstalls()`, a handler that opens `ACTION_MANAGE_UNKNOWN_APP_SOURCES`, a distinct `needs_permission` outcome that survives to the UI, ClipData + install extras on the intent, and an ALLOW action on the INSTALL button. Release APK 1.0.8+9 built and verified with aapt2.
- **errors:** first Kotlin compile failed - `Settings.ACTION_MANAGE_INSTALL_PERMISSIONS` is not a real constant; corrected to `ACTION_MANAGE_UNKNOWN_APP_SOURCES`. Two of my own Dart mistakes: nested the new enum/class inside `UpdatePlatform` instead of at top level, and wrote a test assertion that checked the mock rather than the code.
- **lessons:**
  - `checkSelfPermission` lying about a user-granted permission is the specific trap on Android 8+. The capability API, not the permission API.
  - Reporting success immediately after `startActivity` hides the failure, because the refusal happens in the system UI. Pre-check the grant and report a coded outcome.
  - A `bool` return collapses "you can fix this" and "you cannot" into the same branch. The return type was part of the bug.
- **tags:** updater, android, permissions, fileprovider, release-1.0.8
- **open:** publishing 1.0.8 is blocked - SUPABASE_SERVICE_ROLE_KEY is not in the environment and must not be pasted in chat again. Asked the user to set it locally.

---

## EVT-20261005-0020 - Wire the 5.1 layers into the scan (core function)

- **id:** EVT-20261005-0020
- **timestamp:** 2026-10-05T22:00Z .. 2026-10-05T22:40Z
- **mode:** RESEARCH + BUILD
- **action:** Closed the core-function gap: `ScanRequest` -> `ConfluenceInput` now carries macro and sentiment, and `AnalysisService` feeds the live layers in.
- **result:** The 8.3 overlay is reachable for the first time. With the live read (Fed hike, macro -1 at 73% coverage; COT 37.8th pctile, -1), longs now take `v6DirectionConflict` and shorts receive `macroSupports` + `sentimentSupports`. 281 xau_core tests, 196 app tests, 42 Node tests, both analyzers clean.
- **errors:** `noSuchMethod` in two test repository stubs threw on the new `sentimentLayers()` call, silently failing 11 app tests until the stub was taught the method. Two of my own assertions were wrong rather than the code: one expected `macroAlignment` from a 27%-coverage read (the gate correctly returns null), and another expected macro to resolve from policy+positioning, which is 47% macro-side because positioning is a sentiment layer. Also had to redo a file after PowerShell 5.1 wrote UTF-8 test content as ANSI and corrupted it.
- **lessons:**
  - An input class missing a field makes every downstream consumer of that concept dead code. Trace from the UI backwards to the raw data to find where a chain is broken, not forwards from the newest feature.
  - Test stubs that throw from `noSuchMethod` will turn any new repository call into a silently failing suite.
  - Two weight denominators existing in one system (macro-side 75, all-in 100) is correct but needs a test, because it surprises.
- **tags:** core-function, confluence, scanner, sentiment-layers, wiring

---

## EVT-20261005-0021 - Sentiment layers block in the verdict card

- **id:** EVT-20261005-0021
- **timestamp:** 2026-10-05T23:00Z .. 2026-10-06T00:10Z
- **mode:** BUILD
- **action:** Implemented the approved 5.1 layers block in Flutter and rendered it inside the real AnalysisVerdictCard for a visual check.
- **result:** All four layers with their measured readings, direction badges, coverage chip, and a both-sides agreement strip. 213 app tests pass, analyzer clean.
- **errors found by rendering the real widget (not the prototype):**
  1. The agreement rows were double-flipping `macroAgrees`, which is already side-relative, so both rows inverted whenever there was no candidate direction. Fixed by deriving from the raw alignment; `isLong` now only highlights.
  2. A zero alignment was tagged CONFLICT. Fixed with a distinct NEUTRAL tag.
  3. A blanket regex replace of `harborDivider` also clobbered the `HarborDivider(` widget call, producing `Color(0xFFEDF0F4)()`.
  4. Flutter web will not render from `file://`, and a `Start-Job` HTTP server dies with its parent shell; `Start-Process -WindowStyle Hidden` is what survives.
- **lessons:**
  - A prototype can only exercise the states it renders. Rendering the real widget with a real no-direction verdict found a bug the three-state prototype structurally could not.
  - Do not store a side-relative value and then re-derive side-relativeity downstream. Pass the raw fact and let each consumer orient it.
- **tags:** ui, sentiment-layers, verdict-card, side-awareness, prototype-to-flutter

---

## EVT-20261006-0001 - Sideloaded 1.0.8, fixed a dead feed, and proved the core function on hardware

- **id:** EVT-20261006-0001
- **timestamp:** 2026-10-06T13:50 .. 2026-10-06T14:20
- **mode:** BUILD + VERIFY
- **trigger:** user reported the in-app updater still could not install, with the 1.0.7-era message.
- **actions:**
  1. `adb devices` showed the phone online (Android 16 / SDK 36) with **1.0.6 code 7** installed - older than even 1.0.7. The message they saw was from that build.
  2. Sideloaded the built 1.0.8 APK with `adb install -r -d`, bypassing the in-app updater entirely. Installed as code 9. `appops get com.xauvote.app REQUEST_INSTALL_PACKAGES` -> `allow`.
  3. The screenshot then showed `PostgrestException: Invalid API key` (401): I had built that APK with a placeholder publishable key. Rebuilt with the real one from `supabase_get_publishable_keys` and reinstalled.
  4. Analysis still reported "No analysis yet" with 342 closed 1h bars present. Two defects found: the 60s delay before the first scan, and a thrown error being rendered as a reassuring "waiting for history" message. Both fixed.
- **result:** full pipeline live on the phone - price 4,156.44, a LONG consensus setup with levels, and the analysis card showing NO TRADE / FILTERING with TECHNICAL 5/12, FINAL 8.0, MACRO COVERAGE 73%, all four layers, and `vs LONG CONFLICT / vs SHORT SUPPORTS`. The cron had refreshed the real yield to 2.95% / +5bp.
- **side benefit:** FINAL 8.0 = technical 5 + 2*1 (macro) + 1 (sentiment) confirms the side-aware overlay is working - macro is contributing POSITIVE because the candidate side is short.
- **lessons:**
  - `adb install` is the escape hatch for a broken updater, and it is instant. Reach for it when the updater is the thing under test.
  - The publishable key is not a secret and does not need to be withheld from tooling; only the service-role key does. Conflating the two caused a dead build.
  - Verified the credential against the API before building, next time.
  - "Waiting for enough history" was a false statement about the database. Error text that asserts a cause must not be shown when the cause is unknown.
- **open:** the in-app install path itself is STILL unverified - 1.0.8 is the newest build and is now installed, so there is no update to offer. The permission fix (canRequestPackageInstalls + ACTION_MANAGE_UNKNOWN_APP_SOURCES + ClipData + needs_permission) is in place but untested end to end. Service-role key still needs rotating, and 1.0.8 is still unpublished.
- **tags:** release, adb, install-permission, credential, hardware-verification, core-function

---

## EVT-20261006-0002 - CRITICAL: one seed source was passing as multi-source consensus

- **id:** EVT-20261006-0002
- **timestamp:** 2026-10-06T14:20 .. 2026-10-06T14:30
- **mode:** REVIEW + BUILD
- **trigger:** user redirected from the release to "more important things, like the sources".
- **finding:** `sources` held exactly one row, `manual-seed` (`internal://manual-seed`). `collect-ideas` seeds 636 hard-coded fixture ideas every 15 min with templated reasoning under three fake author names, all sharing one `source_id`. `build-consensus` compared `camp.length` (distinct FINGERPRINTS) against `MIN_INDEPENDENT_SOURCES`, so one publisher posting 9-11 variants passed a "2 independent sources" gate and emitted a live DEVELOPING LONG, strength 86-87, with entry/SL/TP and a COPY LEVELS button. Verified in the DB and on the phone screenshot.
- **fix:** count distinct `source_id`; exclude `internal://` sources from the independence count; score independence in sources too. Deployed and verified.
- **result:** `NO_CONSENSUS / SINGLE_SOURCE`, independence `{ideas:10, distinct_sources:1, distinct_external_sources:0, internal_seed_sources:1}`. Expired the one open setup. Phone shows NO CONSENSUS with no levels.
- **lessons:**
  - A guard named `MIN_INDEPENDENT_SOURCES` compared against the wrong quantity is worse than no guard: it manufactures false assurance. Name and implementation must match.
  - Fingerprints that include `author` cannot detect divided rooms when the source controls the author field. Independence has to be anchored on `source_id`.
  - Synthetic fixtures on a production cron path will eventually be published as real output. The gate must be trustworthy even while the data is fake.
- **tags:** sources, consensus, independence, fabricated-data, critical, correctness

---

## EVT-20261006-0003 - Prepared the source-architecture expert brief

- **id:** EVT-20261006-0003
- **timestamp:** 2026-10-06T14:35
- **mode:** PLAN
- **action:** Wrote `plans/2026-10-06_source-architecture-expert-brief.md` for external consultation, at the user's request.
- **why an expert and not more local work:** the open decisions (product identity, whether to keep a permanently-empty headline feature, whether to reframe "sources" as macro layers, what to do with seed data) are product-strategy and licensing judgements, not code defects. They need an independent view, and they are exactly the kind of decision where a second opinion can catch a premise error.
- **sanitization:** verified clean of credentials, project refs, hostnames and internal identifiers. Only the public domain data sources are named, which is necessary for the expert to reason about them.
- **structure:** six numbered decision-forcing questions, each to be answered as Recommendation / Reasoning / Risks / Alternative / Confidence / Assumptions, with an explicit invitation to disagree with the stated premises.
- **deliberately included:** the independence bug (ideas counted instead of sources) and the live-seeding problem, because both are evidence about how this product misleads and the expert's Q6 depends on them.
- **tags:** expert-consultation, product-strategy, licensing, sources, sanitization

## EVT-20261006-0201 outcome recorder built, deployed and verified end to end

- **mode:** BUILD
- **action:** Built the outcome recorder: protocol pre-registered first, then
  migrations 0008/0009/0010, the `outcome-recorder` Edge Function, and a parity test
  that guards the one unavoidable constant duplication.
- **result:** deployed v5 ACTIVE. rule_hash
  `f7694543642d1f593d2f9e987ed808d7fe37d67328f898ca641a60386585ff87`.
  Settlement branches verified by hand against real m15 bars: TP1, the
  same-bar stop/target tie resolving to STOP, TIMEOUT scored at the horizon close,
  and clustering marking an overlapping second setup as a repeat. RLS confirmed to
  deny anon SELECT, INSERT and the summary view - with a positive control proving
  the key was valid, so the denial was real access control and not a bad key.
  All fixtures deleted; table empty and ready for real decisions.
- **files:** docs/outcome-recorder-protocol.md,
  supabase/migrations/0008_outcome_recorder.sql, 0009_..._notrade_side.sql,
  0010_..._abstained_outcome.sql, supabase/functions/outcome-recorder/index.ts,
  src/app/test/outcome_recorder_parity_test.dart
- **errors:** four real bugs, listed in D-20261006-009. One self-inflicted deploy
  error: a v4 payload referenced an undefined `sideIsLong()` and had dropped the
  whole `settle()` function. Caught before trusting it and re-deployed verbatim from
  the local file in v5.
- **lesson:** hand-writing constants from memory produced two separate serious
  errors in one task - a corrupted engine port and a wrong stop config. The parity
  test existed precisely to catch the second, and did. Duplicated constants need a
  test that fails, not a comment asking people to be careful.
- **tags:** outcome-recorder, measurement, pre-registration, rule-hash, rls

## EVT-20261006-0212 recorder wired into the app; found and fixed a four-day stale-data bug

- **mode:** BUILD / REVIEW
- **action:** Wired the outcome recorder into `AnalysisService.refresh()`, added a
  scheduled settlement job, verified end to end on the device.
- **result:** real decisions now flow (one `NO_TRADE` plus its forced
  counterfactual, genuine spread 0.58 USD, ATR5m 3.18, entry 4162.19 matching the
  live market). The settlement cron ran unattended and closed the pending rows as
  `ABSTAINED`. 250 app tests pass, analyzer clean.
- **bugs found:**
  - The four-day stale-bar truncation in `analysisBars` (D-20261006-010). Severe
    and previously invisible.
  - `OutcomeRecorder` resolved `Supabase.instance.client` in its constructor,
    which made merely constructing an `AnalysisService` throw in 17 tests. Made
    it lazy.
  - Client parameter verification initially assumed a Dart-side SHA-256 hash. That
    was a trap: Dart renders `9.0` as `"9.0"` and `JSON.stringify` renders it
    `"9"`, so every honest row would have VOIDed on float formatting alone.
    Switched to sending the numbers and comparing them server-side.
  - A v4 function deploy shipped referencing an undefined `sideIsLong()` with the
    whole `settle()` function dropped. Caught by re-proving settle after deploy.
- **self-inflicted:** a PowerShell `Set-Content` rewrite of `live_repository.dart`
  mangled a Unicode minus into mojibake and left an unbalanced brace. Reverted
  with `git checkout` and redid the edit with the encoding-safe tool. Lesson: do
  not rewrite whole source files with `Set-Content` in PowerShell 5.1.
- **files:** lib/data/outcome_recorder.dart (new), lib/data/analysis_service.dart,
  lib/data/live_repository.dart, test/outcome_recorder_test.dart (new),
  test/analysis_bars_fetch_test.dart (new),
  supabase/migrations/0011_outcome_recorder_settlement_cron.sql,
  supabase/functions/outcome-recorder/index.ts (v6)
- **tags:** outcome-recorder, stale-data, postgrest-row-cap, regression-guard

## EVT-20261006-0213 spread licence breach closed; found the gate was WRITABLE

   - **mode:** BUILD / REVIEW
   - **action:** Removed the OANDA spread from the client path and made the Radar
     price read live from the provider, as instructed.
   - **outcome:** The display breach is closed, but closing it surfaced a worse
     hole underneath it, and the record below is the point of this entry.
   - **critical - the gate was forgeable:**
     - 0016 revoked `SELECT (bid, ask)` only. A read of the ladder correctly
       failed with 42501 and the work looked finished.
     - It never revoked INSERT/UPDATE/DELETE. A publishable key ships inside the
       app, so it is public. Verified with a VALID JSON body: anon could INSERT a
       row with an invented bid/ask, and PATCH/DELETE existing snapshots.
     - That is worse than the original leak. `spread_gate` would have reported
       "measured and within limits" on the strength of an invented number, and
       the engine's spread veto would have consumed it as genuine.
     - An earlier note claimed "synthetic insert blocked (400)". **That was
       wrong** - the 400 was a JSON parse failure from a malformed test body, not
       a permission denial. Lesson: a 4xx is not evidence of denial; read the
       body, and re-test writes with well-formed JSON.
   - **second read path:** `analysis_scans` and `latest_analysis` each carry their
     own `spread_bid` / `spread_ask` / `spread_value`. Revoking
     `market_snapshots` does not retract a copy written elsewhere. `analysis_scans`
     also granted anon full INSERT/UPDATE/DELETE/TRUNCATE. Nothing in the app or
     in any Edge Function reads these tables and all are empty, so access control
     was the right lever and dropping columns would only have destroyed the
     internal audit record.
   - **fixes applied:**
     - `0017_spread_gate_privileges.sql` (new): table-level revoke on
       `market_snapshots`, then re-grant SELECT on (id, symbol, price, timestamp,
       source) only; recreate `spread_gate` with OWNER security; revoke the four
       unused derived tables; grant writes to `service_role` only.
     - Why owner security: with `security_invoker = true` the view evaluated
       `bid is not null AND ask is not null` as `anon`, which no longer holds
       those columns, so the view could not work at all.
     - Test rows from the forgery probes were deleted; the genuine feed was
       re-checked afterwards (12,685 rows, 5,607 with ladder, still live).
   - **verified by probe, not assumed:** price ALLOWED; bid/ask 42501; gate
     ALLOWED carrying no price; analysis_scans / latest_analysis / spread_status
     42501; forge INSERT, forge scan INSERT, PATCH and DELETE all 42501.
   - **third finding - a fabricated spread on the main screen:** `DisplaySignal`
     had `spread` defaulting to `0.35` and nothing ever assigned it, so Radar
     printed "Spread 0.35" as though measured. The field is removed. Two tests
     were asserting that 0.35 was present, i.e. the fabrication was pinned by the
     suite; one now asserts the opposite.
   - **engine model:** added `VenueSpread.undisclosed` - acceptable but with no
     number. The veto is still evaluated, so a licensing constraint does not
     silently masquerade as a technical one and cost setups. The stop buffer is
     NOT widened without a number, which is the conservative direction.
   - **self-inflicted:** the first `spreadNote` keyed off the spread object while
     `spreadStatus` keyed off freshness, so a stale spread printed a number and
     claimed UNAVAILABLE in the other field. Caught by an existing test. Always
     derive a note and its status from the same gate.
   - **self-inflicted:** asserted `v2SpreadUnevaluated` in `vetoes`; it is emitted
     into `reasonCodes`. The existing test at scanner_test.dart:136 has the same
     weakness - it asserts against `vetoes` and would pass even if the code were
     broken.
   - **key confusion:** the publishable key in circulation notes was mistranscribed
     (`RQuUTHF5Syy` vs the real `RQuuxcbF5Syy`), so every probe returned 401 and
     looked like a permissions problem. `memory/decisions.md` already warns about
     this; the summary had drifted. The key is not a secret and needs no rotation
     - only the service-role key does.
   - **files:** supabase/migrations/0017_spread_gate_privileges.sql (new),
     src/app/lib/data/live_repository.dart, src/app/lib/data/live_data.dart,
     src/app/lib/data/analysis_service.dart, src/app/lib/models/display_models.dart,
     src/app/lib/widgets/harbor_widgets.dart,
     src/app/lib/widgets/analysis_verdict_card.dart,
     src/xau_core/lib/analysis/scanner.dart, src/xau_core/test/scanner_test.dart,
     src/app/test/analysis_service_test.dart, src/app/test/radar_test.dart,
     src/app/test/live_mode_test.dart, src/app/test/events_skeleton_test.dart
   - **tests:** xau_core 285 pass; app 257 pass (was 255); both analyzers clean.
   - **tags:** licensing, least-privilege, forgery, never-fabricate, price-freshness

   - **price path, corrected after the first attempt:** a direct client read of
     gold-api.com worked on the workstation and returned HTTP 429 on the phone at
     the same cadence (16/16 succeeded from the workstation, every attempt 429
     from the phone). The provider rate-limits by client IP, so calling upstream
     per client would fail for most real users. Replaced with a `price-live` Edge
     Function holding a shared single-row cache (`0018_live_price_cache.sql`);
     upstream is hit at most once per 10s regardless of user count.
   - **why this was nearly missed:** `catch (_)` swallowed the 429 and logged
     nothing, so the build looked finished and the app simply fell back to the
     stored snapshot. Only the honesty caption I had just added ("Provider
     unreachable - showing the latest stored snapshot") revealed it on the device.
     Lesson: a fallback that hides why it fired is a defect, and a design verified
     only on the workstation is not verified.
   - **honest limit, recorded rather than papered over:** the provider
     republishes on a ~30s cycle (its own `updatedAt` advances in 30s steps), so
     tick-level "real time" is not achievable with this feed and is not claimed.
     `ageSeconds` is derived from the provider's timestamp, not from the call.
   - **verified on the device (release build, LIVE=true):** price 4,170.30 then
     4,170.40 across 50s, matching upstream exactly at both instants, caption
     "Live from the price provider"; analysis card shows "venue spread measured
     and within limits (16s old); rate withheld under provider licence" and
     "VENUE SPREAD MEASURED - WITHIN LIMITS - RATE WITHHELD (LICENCE)". No spread
     number anywhere, and NO TRADE comes from macro conflict, not a spread gap -
     so setup capability is preserved.
   - **build gotcha:** a release build without `--dart-define=LIVE=true` silently
     falls back to fixtures (`mockMode = !LIVE`). A first "verification" build
     showed the fixture price 4,278.30 and DEMO STATE chips and proved nothing.
   - **files (continued):** supabase/migrations/0018_live_price_cache.sql (new),
     supabase/functions/price-live/index.ts (new, deployed v2),
     src/app/lib/screens/radar_screen.dart
   - **deployed:** spread_gate_privileges (0017), live_price_cache (0018),
     price-live v2.

   - **recorder regression check (important, and it came back clean):** after the
     privilege work, `scan_decisions` had no new row for ~20 minutes and the
     revocations were the obvious suspect. They were not the cause. Checked the
     function logs (`outcome-recorder` = a51c4133, 73 calls, still firing) and
     then the code: `decisionTimeFor(m15)` derives the decision time from the
     newest CLOSED M15 bar, so `decision_key` only changes when a bar closes. The
     19:45 key already existed, so the server correctly deduplicated. The gap was
     expected behaviour, and note 19:30 was already missing before this session,
     which is why the empty stretch should not have been read as new.
   - **recording re-confirmed live:** a fresh pair landed for the 20:00 bar at
     20:05:18, and they carry `spread_status = available` with `spread_value =
     null` - the undisclosed state propagating correctly into the ledger. The
     19:15 row still holds 0.63 from before the fix, which is historical evidence
     in an internal table with no client access.
   - **known limitation carried into the validation protocol:** because the app
     can no longer hold a spread number, it cannot compute `spread_cost_r`, so net
     R will not deduct spread cost once real SETUP episodes start arriving. The
     ledger does not back-fill it either. This makes reported net R slightly
     optimistic. The server CAN read the ladder (service role) and compute it
     internally without ever exposing it, which is the right place for it - but
     that is a change to make deliberately before the first setup is scored, not
     after.
   - **timeout:** `directSpotPrice` timeout raised 6s -> 12s. A real cold Edge
     Function start exceeded 6s and produced a spurious "provider unreachable"
     fallback on a healthy path.
   - **version:** bumped to 1.0.9+10. `decision_key` embeds the client version, so
     a version bump is also what makes the next decision a new key.
   - **build gotcha repeated:** `--dart-define=LIVE=true` is required or the app
     silently serves fixtures.

## EVT-20261006-0214 step 5 verdict: repeated-EXPIRED claim is PARTIALLY CONFIRMED, not reproducing

   - **mode:** RESEARCH
   - **action:** Verified the "repeated EXPIRED rows every few minutes" claim per
     directive �15 before acting on it: row timestamps, cron schedules, function
     error logs.
   - **evidence:** 1,067 EXPIRED rows 2026-10-02 17:55 through 2026-10-06 11:22
     UTC, one roughly every 5 minutes, matching the still-active
     `xv-build-consensus` schedule (`2-59/5`). Zero EXPIRED or INVALIDATED rows in
     the last 6 hours. `build-consensus` still fires (last 19:57 UTC) with no
     error in its logs - it simply writes nothing now.
   - **cause of cessation:** `xv-collect-ideas` was frozen inactive around
     11:10-11:22 UTC (matches the D-20261006 seed-freeze note: newest idea 12:09,
     still 12:09 at 14:10 local). With the seed pipeline stopped, the consensus
     builder had nothing fresh to turn into expiring signals. The pattern died
     with its food supply, not by a code fix.
   - **verdict:** PARTIALLY CONFIRMED historically, NOT REPRODUCED now. No cron
     is currently manufacturing signals: 0 open signals, 0 new rows in 6h.
   - **residual risk (step 6 territory):** `xv-build-consensus` still runs every
     5 minutes. It currently emits nothing, which is the desired behaviour, but
     nothing structural stops it from emitting again if a seeder is ever
     re-enabled. Fixture isolation + the daily canary (�16) are what make this
     stay true.
   - **tags:** verification, expired-rows, cron, step-5

## EVT-20261006-0215 consensus pipeline was silently broken for 10h; fixed, voter wired

   - **mode:** BUILD
   - **action:** Owner authorised FXScalpers as a voter ("green light, no further
     communication"). Before wiring anything, verified the pipeline it would
     feed - and found it broken.
   - **the break:** `build-consensus` returned HTTP 200 every 5 min but wrote no
     `consensus_signals` rows since 11:22 UTC. Root cause from postgres_logs:
     `null value in column entry_low violates not-null constraint` on every
     NO_CONSENSUS audit write. The fail-rows carry no levels (correctly - a
     non-signal must not invent them) but the columns were NOT NULL, so every
     audit insert errored; the function ignored insert errors and reported
     success. Ten hours of silent 200s.
   - **fixes:** migration 0019 makes entry_low/entry_high/stop_loss nullable
     (NULL is the honest value for a non-signal; sentinels would be
     fabrication), and build-consensus v4/v5 now checks every audit insert and
     returns 500 on write failure. Verified: audit rows resumed (1078 -> 1080).
   - **the voter, compliant shape:** automated Telegram collection stays
     REJECTED (platform ToS, D-019 - the green light cannot waive Telegram`s
     rules). Built instead: FXScalpers source row DISABLED (migration 0020),
     `curated_ok` two-pass approval flag (migration 0021 + function filter),
     `enabled` enforced in the independence count (v5), manual curation protocol
     (docs/fxscalpers-curation-protocol.md). Voting needs archived permission +
     enabled source + approved rows; any one missing fails closed.
   - **live voter test (safe):** one clearly-marked TEST idea, enabled source,
     invoked -> SINGLE_SOURCE with distinct_external_sources:1 - the voter
     counts exactly as designed and consensus correctly refused. Test row
     deleted immediately after, source re-disabled, verified zero approved rows
     remain. The SINGLE_SOURCE audit row stays as a truthful run record.
   - **refused, plainly:** automated scraping of the channel under "do whatever
     it needs". Owner instruction cannot authorise violating Telegram`s terms or
     the project`s licensing gate. Manual pipe is what the green light stretches
     to; if hand-entry is unacceptable, there is no path and work stops here.
   - **files:** supabase/migrations/0019_consensus_levels_nullable.sql (new),
     0020_fxscalpers_source_row.sql (new), 0021_curated_approval_flag.sql (new),
     supabase/functions/build-consensus/index.ts, docs/fxscalpers-curation-protocol.md (new)
   - **deployed:** build-consensus v5.
   - **tags:** consensus-pipeline, silent-failure, voter, fxscalpers, manual-curation

## EVT-20261006-0216 FXScalpers source enabled; gate rests on zero approved rows

   - **mode:** BUILD
   - **action:** Owner asserted permission settled and instructed activation.
     Verified zero approved/votable rows first, then set sources.enabled = true
     for FXScalpers. Post-flip invoke: NO_SOURCES, audit row written (total
     1080 -> 1084 with cron runs). Enabling with no rows changes nothing - the
     fails-closed property holds through the third switch.
   - **open:** verbatim reply still not archived. The licence file closes when
     the owner pastes it. No row may be approved before that filing.
   - **tags:** fxscalpers, activation, licence-evidence

## EVT-20261006-0217 market pill lied during the daily halt; price age now shown

   - **mode:** BUILD
   - **action:** Two user-reported defects, both confirmed before fixing.
   - **defect 1 (real bug):** the header showed a live session pill midweek at
     17:30 New York while the venue was halted for rollover. `isSessionOpen`
     modelled only the weekend; the daily 17:00-18:00 New York halt had no rule
     at all. Fixed in the engine (single rule, both consumers), with regression
     tests. Verified on device during the halt: MARKET CLOSED pill, correct
     halt copy, REOPENS IN counting to 18:00 New York.
   - **defect 1b (found while verifying):** the closed card said "closed for the
     weekend" on a Tuesday. Added `closureAt()` (weekend vs dailyHalt, with
     Friday-17:xx and Sunday-17:xx correctly reading as weekend) and separate
     copy on Radar and Signal cards. Same-evening halt vs two-day weekend are
     different waits and now get different words.
   - **defect 2 (not a bug; a ceiling):** the Radar price looked frozen because
     gold barely moved AND the provider republishes on a ~30s cycle (measured:
     21:32:41Z -> 21:33:11Z). The pipe was healthy. MetaTrader-like per-second
     ticks are not achievable at $0 with display-licensable data: OANDA has real
     ticks but its licence forbids display, exchange proxies break instrument
     honesty, and polling harder cannot beat the provider`s own publish cycle.
     So instead of faking motion, the caption now shows the provider-clock age
     ("Live from the price provider - 21s ago"), which ticks every 5s poll and
     proves freshness even when the number sits still. Verified on device.
   - **files:** src/xau_core/lib/analysis/session.dart,
     src/xau_core/test/session_test.dart, src/app/lib/data/live_data.dart,
     src/app/lib/screens/radar_screen.dart, src/app/lib/screens/signal_screen.dart,
     src/app/test/live_mode_test.dart
   - **tests:** xau_core 287 (was 286), app 260. Both analyzers clean.
   - **note:** Gold Hunts session-view integration is mid-flight (migration 0022
     applied without cron, sync function written, NOT deployed, no app changes
     yet). Resume there next.
   - **tags:** session-calendar, daily-halt, price-freshness, honesty-copy

## EVT-20261006-0218 market reopen went unnoticed; session flip watcher added

   - **mode:** BUILD
   - **action:** User reported the app still showed MARKET CLOSED after the
     daily halt ended. Confirmed the mechanism: every screen derives
     open/closed at build time, and builds only happen when polled data
     changes. On a flat stretch nothing rebuilds, so no build ever notices the
     reopen. The user saw the flip only when an unrelated data poll finally
     rebuilt the screens - hence the lag they then reported.
   - **fix:** LiveData runs a 10s session watcher that recomputes
     `isSessionOpen` and notifies ONLY on flip (open->closed or closed->open).
     Two notifications a day, silence otherwise - deliberately not a beat that
     rebuilds screens, which would repeat the Events-list churn bug on purpose.
     Baseline is set silently at start to avoid a pointless rebuild 10s in.
   - **also:** the watcher I first declared was never wired into start/stop
     (interrupted mid-edit), so one build shipped the fields with no timer. The
     lag the user saw was that gap. Wired now; `_sessionTimer` lifecycle
     matches the other three timers. Lesson: an unwired declaration is worse
     than no code, because the diff looks finished.
   - **test:** `checkSession({at})` clock seam - simulated halt-to-open across
     the 18:00 New York boundary notifies exactly once, with silence on either
     side. Tests never call startPolling so no pending-timer failures.
   - **verified on device:** fresh launch into the open market shows green ASIA
     pill, live price with age, NO CONSENSUS (no voters - correct), NO TRADE
     analysis. The flip path itself is covered by the unit test; the next live
     flip is Friday 17:00 New York.
   - **files:** src/app/lib/data/live_data.dart,
     src/app/test/live_mode_test.dart
   - **tests:** app 261, xau_core 288. Both analyzers clean.
   - **tags:** session-flip, auto-detect, notify-on-change

## EVT-20261006-0219 PAUSED: exact resume state for next session

   - **mode:** MEMORY (session handoff)
   - **where everything stands:** Gold Hunts session view is DONE and committed
     (42fb4e2): tables + view + grants live, goldhunts-sync deployed, hourly
     cron active, first sync verified (143 signals, 8 open), app section built
     with 264 app tests green. The ONLY unverified part is seeing the Sources
     section on the physical phone - adb taps would not switch tabs that
     evening (cause undetermined; possibly the owner holding the device), so
     device proof is pending the owner opening Sources by hand.
   - **Finance Calendar status:** review DONE and recorded (D-020: approved as
     convenience layer with attribution, official precedence). Migration 0023
     (provider gate) APPLIED. NOT DONE: the FinanceCalendarProvider in
     fetch-events (map /calendar rows, derive currency from title prefixes,
     numeric-only forecast/previous/actual, slug externalIds), its deploy +
     first-run verify, re-enabling xv-fetch-events cron (currently inactive),
     and the Events-screen attribution line. Next session starts here.
   - **known deferred items (do not lose):**
     1. File the FXScalpers verbatim reply (owner, 10 seconds). Licence file
        open until then; no row may be approved before it.
     2. Gold Hunts outcome reconciliation (�3/�10): archive table exists and is
        filling; independent tally + XV-bar reconstruction not built.
     3. Provider-consensus TEXT ("Hold at 3.50-3.75%") is dropped (no column);
        revisit only if a real display need appears.
     4. Ruling still open: ALIGNED session-context-vote model vs directive �2.
     5. spread_cost_r will be null on future real setups (app cannot hold a
        spread number) - server-side computation is the right fix before the
        first setup is scored.
     6. Next live session flip to observe: Friday 17:00 New York (watcher
        mechanism is unit-tested; live observation pending).
   - **repo state:** tree clean after this commit. Phone runs v11 (1.0.9+11)
     with all client changes. Backend: migrations through 0023, price-live v2,
     build-consensus v5, goldhunts-sync v1, outcome-recorder v10.
   - **tags:** handoff, pause, resume

## EVT-20261006-0220 Sources: resume-refresh, fenced slow sections, named empty header

   - **mode:** BUILD
   - **action:** Two user-reported Sources defects, both confirmed by code
     reading before fixing.
   - **defect 1 (stale until manual pull):** timers do not fire while the app
     is backgrounded, so a returning user reads hours-old slow sections until
     the next 5-minute beat lands. Fix: LiveData observes app lifecycle and
     runs a slow refresh on resume. No fast-cadence changes.
   - **defect 1b (hardening):** slow sections shared one try block, so one
     failing read starved the rest until a lucky full-success pull. Each
     section is now fenced: failures keep previous values and are named in the
     error line, and a partial run no longer clears the error state while full
     success still does.
   - **defect 2 (0/0 with dashes):** with no signal the header printed bare
     0/0 plus dashes that read as a broken widget. Counts stay truthful; the
     tiles now state the absence (NO SIGNAL / NO VOTERS) alongside the existing
     empty-state line.
   - **owner decision recorded:** FXScalpers reply will not be shared; owner
     asserts permission settled and takes full responsibility. Licence file
     closed by owner assertion (amendment to D-017/D-019).
   - **files:** src/app/lib/data/live_data.dart,
     src/app/lib/screens/sources_screen.dart,
     src/app/test/live_mode_test.dart, memory/decisions.md
   - **tests:** app 267. Analyzer clean. New: resume-refresh, section
     isolation, header empty-state widget tests.
   - **device:** rebuilt + installed; fresh launch verified (EUROPE pill, live
     price). Sources section on-device proof still needs the owner`s hand -
     adb taps would not switch tabs.
   - **tags:** sources, resume-refresh, fault-isolation, empty-state

## EVT-20261007-0221 FXScalpers dropped by owner order

   - **mode:** BUILD
   - **action:** Owner ended the candidacy after all three pipes closed
     (manual refused, operator favour declined, scraping rejected). Set
     sources.enabled = false for FXScalpers; row retained as history.
     Verified: zero ideas, zero approvals, consensus behaviour unchanged.
   - **tags:** fxscalpers, dropped, owner-order

## EVT-20261007-0222 Finance Calendar provider live; Events has a real calendar

   - **mode:** BUILD
   - **action:** Implemented directive step 7 (Finance Calendar) after the D-020
     review: FinanceCalendarProvider in fetch-events, deployed, first run
     upserted 16 real rows, xv-fetch-events cron re-enabled (hourly :07),
     attribution line on the Events screen.
   - **mapping honesty points:** no currency field in payload - derived from
     title prefixes for majors, UNKNOWN otherwise (fail closed under the
     USD/EUR/GBP chips; never guessed). consensus/prior/actual stored only
     when numeric (provider sends strings like "6.4% unemployment" or null);
     surprise therefore reads unavailable until real figures arrive. all-day
     rows take date at 00:00 UTC. Impact unknown defaults LOW (can never trip
     the blackout guard). Provider-consensus TEXT ("Hold at 3.50%-3.75%") is
     deliberately not stored - no column, display deferred until a real need.
   - **guard note:** build-consensus blackout does not filter currency, so a
     HIGH non-USD release (e.g. Canada Labour Force Oct 9, Australia Oct 14)
     will suppress emission like a US one. Kept as-is: conservative direction
     (suppresses, never creates), gold reacts to major global prints. Recorded
     here rather than silently changed.
   - **not device-verified:** adb taps still would not switch tabs, so the
     Events/Sources on-phone sighting remains with the owner. Widget tests
     cover rendering; DB rows verified by query.
   - **files:** supabase/functions/fetch-events/index.ts,
     supabase/migrations/0023_finance_calendar_provider.sql (applied),
     src/app/lib/screens/events_screen.dart
   - **deployed:** fetch-events (FinanceCalendar default; FMP still gated).
   - **tests:** app 267 green, analyzer clean.
   - **tags:** finance-calendar, events, blackout-guard, attribution

## EVT-20261007-0223 news seeder was fabricating the macro backdrop; removed

   - **mode:** BUILD
   - **action:** Three Events complaints investigated; the worst was a live
     fabrication incident.
   - **incident:** news-collect ran ManualNews as its DEFAULT provider every 30
     min, writing invented "Manual Desk" headlines with example.com links into
     production news_articles - and news-digest summarized those inventions
     into the on-screen macro themes (live proof: a "Fed policy repricing"
     theme evidenced ONLY by example.com seed URLs). Same class as the retired
     calendar fixtures and the 0.35 spread. Fixed: ManualNews unreachable in
     production (function reports empty when unconfigured), seed rows deleted
     (articles and poisoned digests both back to 0), xv-news-collect and
     xv-news-digest crons disabled, digest refuses example.com rows as
     defense in depth.
   - **results tab:** honestly empty and stays so for now - the provider
     publishes NO actuals (verified: week-old releases still null despite docs
     claiming hourly fills). The empty state now says why instead of reading
     broken.
   - **coverage:** fetch window widened 8d -> 14d forward (25 real rows). No
     past window: past rows carry no actuals either, so they would add noise,
     not results. Earnings excluded from the API by the provider (documented).
   - **news clarity:** empty states name the cause (no licensed $0 news feed;
     GNews free is non-commercial); theme rows now show their evidence count
     ("N linked articles") so a theme reads as a summary, not a verdict.
   - **files:** supabase/functions/news-collect, news-digest, fetch-events,
     src/app/lib/screens/events_screen.dart, test/live_mode_test.dart
   - **deployed:** all three functions; news-collect verified dry
     (provider:none, stored:0); fetch-events verified (25 rows).
   - **tests:** app 267 green, analyzer clean.
   - **tags:** fabrication-incident, news-seeder, honest-empty, coverage

## EVT-20261007-0224 calendar cross-check live; first findings triaged, cron daily

   - **mode:** BUILD
   - **action:** Built directive step 8 (official-source validation) as
     calendar-crosscheck: daily Finance Calendar HIGH USD vs l3vlup
     official-schedule comparison, findings to calendar_discrepancies (0024),
     cron xv-calendar-crosscheck 07:30 UTC. Never auto-corrects; questions
     only.
   - **matcher lessons from first runs (kept):** match presence across impact
     scales (FC calls PPI medium, validator high - a scale difference is
     judgment, not a factual gap); window the reverse check to our fetch range
     (validator file spans months; flagging November in October is noise);
     ET->UTC with real DST math.
   - **first findings (2, both triaged DISMISSED with notes):** retail sales has
     no validator counterpart (Census, outside l3vlup BLS/BEA/Fed sources -
     standing limitation: Census releases cannot be validated this way); state
     employment Oct 20 has no FC counterpart (Tier-2 BLS FC does not curate -
     no guard impact). Neither is a data error; both stay as documented rows.
   - **files:** supabase/functions/calendar-crosscheck/index.ts (new),
     supabase/migrations/0024_calendar_discrepancies.sql (new, applied)
   - **deployed:** calendar-crosscheck v3 (v1 unwindowed, v2 windowed,
     v3 impact-blind matching). 15 noisy first-run rows deleted before the
     matcher was fixed; clean baseline re-run verified.
   - **tags:** validation, crosscheck, calendar, step-8

## EVT-20261007-0225 browser testing works; first run caught a CORS-only outage

   - **mode:** BUILD
   - **action:** User asked to test in browser instead of per-change APK
     installs. Made it real: update_service.dart was the only non-web import
     (dart:io throughout); added update_io_stub.dart behind a conditional
     import so it compiles for web while remaining Android-only by
     construction (main provides no UpdateService without a manifest URL).
     Lesson: conditional imports resolve the DEFAULT uri in analysis - stub
     first broke every VM type; dart:io first works everywhere.
   - **proving run caught a real bug:** the web build rendered fully but showed
     "Provider unreachable" while the phone was live. Root cause: price-live
     was called with the key in an `apikey` header, forcing a CORS preflight
     the gateway answers without echoing the header - every browser refused
     while Android (no preflight) worked. Fixed by sending the public anon
     key as a query parameter with zero custom headers (simple GET, no
     preflight), pinned by a MockClient regression test asserting URL shape
     and header absence.
   - **workflow from here:** `flutter build web --release` + serve build/web
     on 8901, drive at http://10.10.0.4:8901/ via DevTools (MCP browser
     reaches LAN, not localhost; Start-Job does not survive between shell
     calls so the server runs via detached Start-Process).
   - **files:** lib/services/update_service.dart, lib/services/update_io_stub.dart (new),
     lib/data/live_repository.dart, test/live_mode_test.dart
   - **tests:** app suite green incl. new preflight-shape test.
   - **tags:** web-testing, cors, conditional-imports

## EVT-20261007-0226 results tab filled with real scored releases

   - **mode:** BUILD
   - **action:** User reported empty News + Results tabs. Found the provider
     DOES publish actuals, but only as descriptive text with a multi-week lag
     (Sept 30 rows still null, mid-August populated) - and fetch-events was
     dropping them (numeric-only parse). Also D-20261006-020''s "actuals within
     an hour" claim was wrong; corrected in D-20261007-023.
   - **changes:** migration 0025 (actual_text, actual_source); fetch-events
     60-day back window + verbatim actual_text + clobber guard so hourly
     upserts never erase BLS numerics; new daily bls-actuals job (13:35 UTC
     cron) scoring CPI (CUUR0000SA0), payrolls (CES0000000001), unemployment
     rate (LNS14000000) from the BLS public API under a vintage rule
     (reference month strictly before event month, M13 annual averages
     excluded, first-write-wins); app resultEvents() + live results field +
     Results pane with wording/provenance lines; _surpriseLine UNSCORED for
     null surprise (was falsely "IN LINE" without a forecast).
   - **verified live:** fetch-events upserted 108 rows; bls-actuals scored 4
     (Oct 2 NFP 159044 ref M09; Sept 11 CPI 334.98 ref M08 + publisher text
     "+0.1% MoM, 3.4% YoY"); dozens of rows carry provider wording (FOMC,
     retail, BoE...). App analyzer clean, 268 tests green incl. new Results
     rendering + empty-state tests. New APK installed on phone; web build
     live on :8901 (synthetic taps don''t reach Flutter gestures, so the
     RESULTS screenshot is left to the phone).
   - **files:** supabase/functions/fetch-events/index.ts,
     supabase/functions/bls-actuals/index.ts (new), migration
     0025_bls_actual_source, lib/data/live_repository.dart,
     lib/data/live_data.dart, lib/models/display_models.dart,
     lib/screens/events_screen.dart, test/live_mode_test.dart
   - **tags:** results, bls, actuals, surprise-honesty, vintage-rule

## EVT-20261007-0227 all countdowns tick on their own clock

   - **mode:** BUILD
   - **action:** User reported every countdown static. Two root causes: (1)
     EventCountdown ticked to the next minute boundary while DISPLAYING
     seconds, freezing up to 60s at a time; (2) the Radar caution line,
     Events guard summary, row meta lines, and Signal guardrail bar were
     plain interpolated text that only refreshed when LiveData notified -
     which it deliberately does not do on unchanged polls. Fix: sub-day
     countdowns tick every second; all four static sites converted to
     self-ticking EventCountdown (inline via RichText WidgetSpan where the
     clock sits mid-sentence); widget gained a style override + injectable
     clock for tests. Also fixed a latent formatter bug: multi-day printed
     "6d 03:h" (dropped minutes) instead of "6d 03h".
   - **verified:** analyzer clean; 270 tests green incl. two new ones - one
     advances the injected clock 5s with no poll and asserts 12:41->12:36,
     one pins the multi-day format. Fresh APK installed on the phone.
     Honest limit: no sub-day HIGH countdown is live right now (next is Oct
     14 CPI), so second-hand movement on device can only be eyeballed once a
     nearer release exists; the ticking proof is the automated test.
   - **files:** lib/widgets/harbor_widgets.dart (EventCountdown, guardrail
     bar), lib/screens/radar_screen.dart (caution), lib/screens/events_screen.dart
     (guard line, meta line), lib/models/display_models.dart (formatter),
     test/live_mode_test.dart
   - **tags:** countdown, ticking, frozen-clock, widgetspan, testable-clock

## EVT-20261007-0228 radar values fixed: server-side session stats + filled day move + 1s repaint

   - **mode:** BUILD
   - **action:** User reported wrong price/high/low/range, then blank day
     move, then demanded >=1s updates. Found the range read newest-N rows
     through the PostgREST page cap, silently shrinking the window as the
     session grew (morning spike fell out by afternoon). Fix: new
     xv_session_stats RPC (0026 + grant 0027) aggregates lo/hi/first-print/
     prev-close in one round trip; LiveData re-anchors every slow poll and
     folds each price tick locally between polls. Day move now reads vs the
     previous close (pinned per session so retention pruning cannot march it
     mid-session), blank only with no reference. Quote+day bar repaint every
     second on their own ticker (values move with ticks; the feeds cap at
     ~30s/60s so sub-second data does not exist at $0 - stated, not faked).
   - **verified live:** v14 clean install, verified-fresh process: RANGE
     4,068.18-4,170.50 == RPC truth to the cent; DAY MOVE -48.79 ==
     price-prev_close exact; hero % -1.17% consistent; ticks track across
     screenshots; countdowns tick. App suite 273 green, analyzer clean,
     xau_core 291 green (incl. 3 new sessionStartUtc tests).
   - **process hygiene (hard lesson):** an afternoon of ghost screenshots -
     installs do not kill running processes, `am start` re-attaches with a
     "top-most instance" warning my truncated output hid, and versionCode 11
     on every build made dumpsys useless. From now: full outputs, pidof
     before/after every kill/start, version bump per test build, uninstall
     (not install -r) for clean verification. Also: LIVE=true is mandatory -
     builds without it are mock (the 4278.30 web incident).
   - **files:** supabase/migrations/0026_session_stats_rpc.sql,
     0027_session_stats_grant.sql, supabase/functions (unchanged),
     src/xau_core/lib/analysis/session.dart (+sessionStartUtc),
     src/xau_core/test/session_test.dart,
     src/app/lib/data/live_repository.dart (+sessionStats/sessionPrices/
     previousClose), src/app/lib/data/live_data.dart (tracker, pinning,
     shared tick path), src/app/lib/screens/radar_screen.dart (move, hero
     pct, 1s quote block), src/app/test/* (fold/pin/blank tests)
   - **tags:** radar, range, day-move, rpc, postgrest-cap, pinning, 1s-ticker, process-hygiene

## EVT-20261007-0229 inspected external free-gold-API advice, verified each claim live

   - **mode:** RESEARCH
   - **action:** User pasted external advice (4 free gold APIs). Verified all
     four endpoints live + read the actual ToS for three. Corrections: (1)
     goldprice.dev free tier bans redistribution to third parties (ToS S6) -
     the advice omitted this, and it disqualifies free use in our published
     app. (2) biquote 15k/min + unmetered WS confirmed in their ToS; its MT5
     broker sourcing is covered by an explicit display/commercial grant, but
     the third-party-source caveat is recorded. (3) xaus.com has no findable
     licence text - usable only after written confirmation. (4) gold-api.com
     "unlimited" is real but the feed republishes ~30s - the ceiling stands.
   - **result:** D-20261007-024 approves biquote (REST-first) with gold-api
     as mandatory fallback. No code written; implementation awaits user
     go-ahead.
   - **tags:** licensing-review, price-feed, biquote, verification

## EVT-20261007-0230 biquote live as primary price (2s-old ticks)

   - **mode:** BUILD
   - **action:** User approved biquote integration. price-live now tries
     biquote first (mid only, gated on stale=false and quote age <=20s by
     both their clock and ours, 8s fetch timeout, never throws past the
     gold-api fallback), gold-api second, stored snapshot last. Cache 5s.
     App plumbs the source label through to the Radar caption
     ("Live - biquote - 4s ago") as the ToS-appreciated attribution.
   - **verified live:** price-live returns source=biquote ageSeconds=2
     (was 22-28s); direct biquote mid 4105.45 age 0s confirms the read;
     v15 clean install, verified-fresh process: caption names biquote,
     price/range/move/% all correct, countdowns tick. App suite 273 green,
     analyzer clean.
   - **files:** supabase/functions/price-live/index.ts,
     src/app/lib/data/live_repository.dart (+source),
     src/app/lib/data/live_data.dart (+priceSource),
     src/app/lib/screens/radar_screen.dart (caption), tests (stub + caption)
   - **tags:** biquote, price-feed, provenance, attribution

## EVT-20261007-0231 day-move anchor made visible

   - **mode:** BUILD
   - **action:** User read correct behavior as a bug: the move tracks every
     price tick against a fixed reference while the extremes only widen, but
     the reference was invisible so it looked arbitrary. Verified on device
     first (two shots 9s apart: move -46.51 -> -46.61 exactly matching price
     -0.10, reference pinned at 4152.47, extremes static - all correct).
     Fix is display-only: the Day Move cell now carries "vs close 4,152.47"
     (or "vs first print ..." on fallback, nothing with no reference), and
     LiveData exposes the reference kind. Math untouched.
   - **verified:** analyzer clean, 273 tests green (anchor + no-anchor
     cases); v16 clean install, verified-fresh process shows the anchor and
     consistent figures.
   - **files:** lib/data/live_data.dart (+dayReference/dayReferenceIsClose),
     lib/screens/radar_screen.dart (_cell sub, _moveSub), test
   - **tags:** day-move, provenance-display, ux-clarity

## EVT-20261007-0232 news tab filled with licensed issuer headlines

   - **mode:** BUILD
   - **action:** User researched free news options (Fed/BLS/BEA/Treasury RSS +
     MINING.com). Verified each live: Fed/BEA/MINING-main OK, BLS 403 from
     workstation but 200 from edge, MINING gold-tag 404 (used commodity/gold
     which works from here but 403s edge), Treasury 406. Implemented
     RssIssuerProvider in news-collect (Fed monetary + speeches with
     relevance gates, BLS empsit + cpi, BEA, MINING gold) with per-feed
     tolerance, feed counts + named warnings. Debugged BLS silence in situ:
     unclosed entries (split parsing) then a real one-line bug where the
     href fallback only ran for truthy-but-bad urls, dropping all href-only
     BLS links. Result: 90 articles (Fed 19 incl. today''s FOMC minutes,
     BLS 24 NFP+CPI, BEA 47); digest themes now evidence real issuer URLs.
     App empty-state copy updated (licensed feeds active).
   - **verified:** run responses with feedCounts; DB spot checks (NFP
     +29,000 Oct 2, CPI rows); digest 5 themes with real evidence;
     analyzer clean, 273 tests green; v17 installed (NEWS visual left to
     owner - tabs untappable via adb).
   - **files:** supabase/functions/news-collect/index.ts,
     src/app/lib/screens/events_screen.dart (copy), tests, memory
   - **tags:** news, rss, licensing, bls-debugging, in-situ-diagnostics

## EVT-20261007-0233 service-key rotation verified + first public release cut

   - **mode:** BUILD
   - **action:** User completed dashboard rotation; CLI secrets-set correctly
     refused (SUPABASE_ prefix is reserved/auto-injected). Found the second
     key copy before it broke: cron jobs invoke functions through
     vault.xv_service_role_key, which does NOT follow dashboard rotation.
     User updated the vault secret via SQL editor. Verified end-to-end:
     price-live (biquote 1s), bls-actuals writes, cron-path invoke, and all
     scheduled runs succeeding post-rotation (tick/consensus/bars/quotes/
     settle). Then tagged v1.0.10 and published GitHub Release with the
     sideload APK + honest notes.
   - **files:** release v1.0.10 (app 1.0.10+18), memory
   - **tags:** key-rotation, vault, release, github-release

## EVT-20261007-0234 browser round: CORS fix verified, keyboard nav mapped, 4 user questions answered in code

   - **mode:** BUILD
   - **action:** User asked 4 questions (signals provenance, news freshness,
     results missing dates/figures, upcoming coverage). Answered each in
     code: (1) History header now states "Last 50 closed signals" + what
     no-vote expiries mean. (2) Wired the missing headlines pipeline
     (repo.latestHeadlines -> LiveData slow section -> NEWS tab) - articles
     existed but nothing read them. (3) Results cards show release date/time
     + publisher wording as the figure fallback. (4) Upcoming states its
     coverage ("11 of 24 - filters hide the rest") and repo limit raised
     past the window. Fixed a second CORS outage found via DevTools network
     (outcome-recorder POST refused on web; plain-HTTP call + ACAO header on
     the function) - verified POST 200 in browser. Keyboard Tab+Enter drives
     bottom-nav tabs in the demo (sub-tab pills are not focusable).
   - **verified:** analyzer clean, suite green (incl. updated NEWS/Results/
     prose-skip tests); browser network all-200 incl. headlines query,
     session-stats RPC, outcome-recorder POST; screenshots of Radar,
     Upcoming (coverage note live), History (new caption live).
   - **files:** lib/data/outcome_recorder.dart, lib/data/live_repository.dart
     (+latestHeadlines), lib/data/live_data.dart (+headlines), lib/screens/
     events_screen.dart (headlines wiring, results date/wording, coverage),
     lib/screens/history_screen.dart (caption), supabase/functions/
     outcome-recorder (ACAO), tests
   - **tags:** browser-testing, cors, headlines, results-dates, coverage-honesty

## EVT-20261008-0235 entity decoding at ingest; results-tab grey-box report open

   - **mode:** BUILD
   - **action:** User reported an expanding grey box on Results that shows/
     hides. Inspected the live Results tab in the demo (keyboard navigation
     mapped): guard bar compact, result cards correct with dates, wording,
     provenance, UNSCORED - no defect visible across captures. Fixed one real
     visible defect found en route: publisher HTML entities shown raw
     ("Citizens&#8217;") - now decoded at ingest in fetch-events with
     automatic backfill of existing rows (verified 0 entity rows remain).
     NOTE: phone runs v17 (adb down, v18+ never installed) so the grey box
     may be stale-client behavior; demo is current. Asked user for the
     trigger (scroll/tab-switch/pull timing) to reproduce.
   - **files:** supabase/functions/fetch-events/index.ts (decodeEntities),
     memory
   - **tags:** entities, results-tab, unverified-report, stale-client

## EVT-20261008-0236 guard line removed from Results tab

   - **mode:** BUILD
   - **action:** User asked to remove the EVENT GUARDRAIL bar from Results
     after the flicker root stayed unproven. Agreed on product grounds too:
     an upcoming-blackout countdown has no business above past results. The
     bar now renders on Upcoming only; blackout info remains on Upcoming,
     Radar caution, and the Signal guardrail bar. Suite green, demo rebuilt.
   - **files:** lib/screens/events_screen.dart
   - **tags:** results-tab, declutter, guardrail-scope

## EVT-20261008-0237 indicators mockup presented, no app code touched

   - **mode:** PLAN
   - **action:** User requested major indicator signals + user customization,
     mockup first. Built docs/mockups/mockup-13-indicators.html (Harbor
     styling per ui-design playbook): A) Signal-screen confluence card with
     6 tiles (RSI/MACD/Bollinger/Stochastic/EMA/ATR), timeframe pills,
     threshold gauges; B) Settings customization (toggles + parameter
     steppers + reset). Interactive (tiles hide, params sync, TF swaps
     values). Served on :8902, verified by screenshot.
   - **product position baked in:** indicators are CONTEXT ONLY and never
     vote/confirm/flip (rules 1/5/9); display-only customization that never
     touches consensus math, guard, or validation; values computed from
     real bars (600-deep history exists). Awaiting user approval/changes
     before any implementation.

## EVT-20261008-0238 mockup 13R reflects the approved regime stack

   - **mode:** PLAN
   - **action:** User confirmed both questions (drop BB/Stoch for ADX+VWAP;
     FRED key acceptable). Rebuilt the mockup as 13R: regime-worded tiles
     only (bullish/bearish/ranging - LONG/SHORT reserved for consensus),
     timeframe tag on every technical reading, slow-sentiment minis with
     their own cadence labels, activity renamed from volume, settings
     re-cut to the approved layers + sentiment feed toggles. Verified by
     screenshot (sections + settings). No app code touched; awaiting build
     approval.

## EVT-20261008-0239 regime stack implemented from mockup 13R (Phase 1)

   - **mode:** BUILD
   - **action:** User approved implementation pixel-by-pixel. Built: xau_core
     regime engine (VWAP session-anchored with volume honesty, activity
     ratio, fractal structure classification, 4-vote agreement with MIXED
     default, RSI 65/35 lean bands, ADX strength-only) + 11 engine tests;
     AnalysisService per-TF regime map; AppState indicator prefs (7 toggles,
     14 params, persistence, reset); Signal context card (two-panel gradient
     summary, tiles with gauges, TF pills, pending sentiment card);
     Settings customization group with steppers. Sentiment feeds deferred
     to Phase 2 (needs user FRED key + COT job) - card shows pending,
     never sample values.
   - **verified:** analyzer clean; app 281 + engine 302 green; browser demo
     on REAL bars: MIXED 2/4 split card with sensible note, tiles, TF pills.
     Fixed along the way: VWAP equality counts neutral (test caught it);
     summary fixed-height against stretch crash in lists.
   - **files:** xau_core/lib/analysis/regime.dart + test, app
     models/regime_display + test, widgets/regime_card, screens
     signal/settings, state/app_state, data/analysis_service
   - **tags:** indicators, regime, mockup-13R, phase-1

## EVT-20261008-0240 regime build installed on phone (v19)

   - **mode:** BUILD
   - **action:** adb back; built 1.0.10+19 from current HEAD, uninstalled,
     installed, verified fresh process. Phone shows live biquote price,
     filled day move, session range, ticking countdowns, honest NO
     CONSENSUS. Regime card on Signal tab for owner review.
   - **tags:** install, release-build

## EVT-20261008-0241 regime customization moved inline to Signal screen

   - **mode:** BUILD
   - **action:** User asked to move indicator settings next to the readings
     instead of app Settings. Added an inline Customize panel on the regime
     card (toggles + steppers + reset, same prefs, same recompute path) and
     removed the Settings group. Verified live in demo: summary card, TF
     pills, layer tiles with real computed values; Settings shows no
     indicator group.
   - **tests:** suite green incl. new inline-toggle test; fixed a
     time-rotted fixture (bars now dated back from now) and a lazy-list
     scrolling trap in the settings regression test.
   - **files:** lib/widgets/regime_card.dart (+customize), lib/screens/
     settings_screen.dart (-219 lines), tests
   - **tags:** customization, colocation, settings-cleanup

## EVT-20261009-0242 in-app updater fixed end to end

   - **mode:** BUILD
   - **action:** User reported the internal updater broken. Found the real
     cause chain: no manifest endpoint ever existed (builds shipped without
     UPDATE_MANIFEST_URL, so the panel honestly read UNAVAILABLE). Built the
     channel: public gist manifest + v1.0.10 release assets. Hit two real
     obstacles: (1) repo is PRIVATE so raw.githubusercontent 404s
     anonymously -> gist instead; (2) --dart-define values arrive empty in
     Android release AOT builds (proven: same flags work in tests + web,
     verbose build shows them passed to gen_snapshot, binary contains the
     string, runtime still empty) -> moved the endpoint into public
     app_config table (migration 0028) read at startup, define kept as
     fallback. Verified on phone: CHECK offered, manifest fetched, compare
     correct ("Version 1.0.10 is current").
   - **release:** v1.0.10 assets XV-v1.0.10-20.apk + XV-v1.0.10-21.apk;
     manifest tracks 21; phone on 21.
   - **files:** supabase/migrations/0028_app_config_table.sql,
     lib/services/backend_service.dart (+updateManifestUrl),
     lib/main.dart (DB-first endpoint), updates/xv-manifest.json (mirror)
   - **tags:** updater, manifest, dart-define-android, app-config, release

## EVT-20261009-0243 offline detection + calm analysis card

   - **mode:** BUILD
   - **action:** User reported no offline detection. Reproduced live via
     airplane mode: price froze with no banner, plus logcat showed an
     unhandled async crash-loop (fallback query throwing inside the catch).
     Fixed: directSpotPrice reports reachability explicitly with a guarded
     fallback; LiveData tracks backend reachability (offline flag, recovers
     on success); network failures mark offline instead of printing stack
     traces when data exists; HarborOfflineBar on Radar/Signal/Events;
     analysis card shows calm "Waiting for connection" instead of the red
     exception box when offline. Verified on device offline (banner, honest
     blanks, no red box) and after reconnect (banner clears, all values
     exact, logcat clean). Suite 287 green.
   - **files:** lib/data/live_repository.dart, lib/data/live_data.dart,
     lib/widgets/harbor_widgets.dart (+HarborOfflineBar), lib/widgets/
     analysis_verdict_card.dart (+offline), screens x3, tests
   - **tags:** offline, airplane-mode, crash-loop-fix, verification

## EVT-20261009-0244 release hygiene: versioned APK filenames

   - **mode:** BUILD
   - **action:** While cutting v1.0.11 the download filename carried the
     version string only, so two different builds collided under one name
     and a stale file survived across a release. Filenames now include the
     versionCode (xv-1.0.11-24.apk), making collisions impossible; checksum
     still gates install. Verified: correct binary uploaded (hash
     round-trip matches manifest), release carries exactly one asset.
   - **files:** lib/services/update_service.dart, test/update_service_test,
     pubspec 1.0.11+24
   - **tags:** updater, filename-collision, release-hygiene

## EVT-20261010-0245 v1.0.11 released, in-app update loop closed on device

   - **mode:** BUILD
   - **action:** User asked for a shareable release. Cut v1.0.11
     (1.0.11+24): regime stack, offline detection, DB-driven updater.
     Caught a real release bug en route: I uploaded the wrong binary first
     (stale temp path), caught by re-downloading the asset and hashing it.
     Fixed naming (versionCode in filename) plus manifest. Verified the full
     loop on the phone: CHECK -> 1.0.11 available -> download 49MB ->
     checksum -> system installer. One device-side anomaly noted: two
     installer "success" screens never committed (version frozen); adb
     install of the identical bytes committed instantly, so the APK and
     signature are good - likely a stale-file/installer-session quirk on
     this Samsung, now moot since the filename fix prevents stale reuse.
     Final state verified: phone on 24, updater reports current.
   - **link:** https://github.com/amworx/xau-vote/releases/tag/v1.0.11
   - **tags:** release, updater-e2e, checksum-verified, samsung-quirk
