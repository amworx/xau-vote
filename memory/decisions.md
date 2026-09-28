# Decisions

---

## D-20260926-001 — Project root folder name

- **date:** 2026-09-26
- **decision:** Project root is `C:\Users\HP\Documents\code_repo\xau-radar\` (lowercase, hyphenated, no spaces), NOT the pre-existing `XAU Radar\` folder which holds only the original spec file.
- **rationale:** Spaces in folder names cause friction with Flutter/Dart tooling, CI, and shell scripting. The original `XAU Radar\` folder is preserved untouched as the source container; the spec was copied to `docs/mvp-specification.md`.
- **status:** accepted

## D-20260926-002 — No remote, local git only

- **date:** 2026-09-26
- **decision:** Git initialized locally on branch `main` with repo-local identity. No GitHub remote for now.
- **rationale:** Matches pattern of other new projects in the container (durus, ditin). Remote can be added later when the repo goes public/private on GitHub Free.
- **status:** accepted

---

## D-20260927-003 — Pip convention for XAUUSD displays (REVISED)

- **date:** 2026-09-27, revised 2026-09-28
- **decision:** Pip size is a **user setting** with two options — **A: 1 pip = 0.10** or **B: 1 pip = 0.01** — **defaulting to B** per user (FXPro/Vantage trader). All mockup figures use B-default, computed from the 4,278 entry reference (spec §11 example): SL 4,262 → −1600 pips; TP1 4,295 → +1700; TP2 4,315 → +3700; TP3 4,340 → +6200; entry zone 4,275–80 → 500-pip zone; live P&L at 4,278.30 → IN-PROFIT +30 pips. Switching the setting multiplies all pip displays ×10 or ÷10 from the single point-based source of truth (points never change).
- **rationale:** User directive; brokers differ and traders think in their own broker's pips. Points (spec §11) remain the canonical internal unit; pips are display-only.
- **status:** accepted
