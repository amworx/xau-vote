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

## D-20260927-003 — Pip convention for XAUUSD displays

- **date:** 2026-09-27
- **decision:** 1 pip = 0.10 price units for all XAUUSD pip displays. Distances computed from the 4,278 entry reference (spec §11 example): SL 4,262 → −160 pips; TP1 4,295 → +170; TP2 4,315 → +370; TP3 4,340 → +620; entry zone 4,275–80 → 50-pip zone. Live P&L vs entry ref (e.g. 4,278.30 → IN-PROFIT +3 pips).
- **rationale:** User directive ("pips are crucial for TP and SL"). 0.10 matches the most common retail (MT4/MT5) gold convention. If the user's broker counts pips differently, this decision gets revised and all displays recomputed from the single reference.
- **status:** accepted — pending user confirmation of broker convention
