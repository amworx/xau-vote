
---

## Unbounded reads fail silently, and they fail toward looking correct

An unbounded ordered read from a growing table is not a neutral default. Capping
the row count keeps whichever end of the sort survives the cap, so ordering
ASCENDING plus a server-side cap keeps the OLDEST rows and quietly serves stale
data. The failure mode is a short response, not an error: nothing throws, nothing
logs, and the UI renders perfectly. It also degrades as the table grows, so it
gets worse on exactly the timeline you care about.

Two rules that follow:
- Order newest-first and always bound the request, so a cap costs extra history
  instead of the current price.
- Never assume you can discover a platform limit by asking the platform's own
  configuration. `current_setting('pgrst.db_max_rows')` was NULL on this project
  while a 1000-row cap was demonstrably in force.
