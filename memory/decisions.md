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
