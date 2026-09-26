# Playbooks

---

## PB-001 — Initialize a new project in the code_repo container

1. Confirm container folder, project name, and derived `project_root` with the user before creating anything.
2. Ask stack/architecture if not already defined by a spec.
3. Create: `AGENTS.md`, `docs/`, `plans/`, `tasks/`, `src/`, `memory/` with the 5 memory files (events, lessons, patterns, decisions, playbooks).
4. Never install packages, scaffold frameworks, or create lock files / node_modules / venvs unless explicitly requested.
5. If a spec file exists elsewhere, copy it into `docs/` (keep the original untouched).
6. Write project `AGENTS.md`: stack table, structure, core product rules, safety rules, inheritance note.
7. `git init` → set repo-local identity (`git config user.name/user.email` — this machine has no global identity) → `git branch -m main` → root commit.
8. Record EVT (events.md) + any decisions (decisions.md).

**Reusable from:** EVT-20260926-0001 (xau-radar init, 2026-09-26)
