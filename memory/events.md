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
