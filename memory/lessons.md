
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

## "Correct in the database" is not "correct in the product"

I spent several days reporting work as verified while checking tables, row counts
and test results rather than the screens the owner actually looks at. Two real
faults shipped that way: the app analysed four-day-old bars, and the Events tab
rendered computed fixture dates as a calendar.

The test suite passing is evidence about the code, not about the product. Row
counts matching is evidence about storage, not about what is displayed. For
anything user-facing, the check has to be the screen, and a full data-to-screen
trace that nobody has performed yet is a known unknown, not a passing suite.
