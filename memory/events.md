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
