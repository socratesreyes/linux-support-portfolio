-- =============================================================
-- MySQL Support Queries
-- =============================================================
-- Lab queries mapped to a support dataset:
--   clients, users, cases, transfers (+ transfers_bulk for
--   performance drills only).
--
-- Purpose: support-triage queries a Technical Support Engineer
-- would run during a ticket. Not analytics, not reporting.
-- Every query is labeled with the ticket scenario it supports
-- and a short note on how to read it.
--
-- Conventions:
--   - Read-only by default. Writes are separate and deliberate.
--   - Always bound time ranges. Unbounded scans age poorly.
--   - Use LIMIT during triage; remove it only for reporting.
--   - Comment the intent, not the syntax.
-- =============================================================
-- -------------------------------------------------------------
-- 0. Sanity checks (run first, run often)
-- -------------------------------------------------------------
-- 0.1 Confirm you're on the right server and database.
SELECT
  @@hostname            AS host,
  @@port                AS port,
  DATABASE()            AS db,
  CURRENT_USER()        AS user,
  NOW()                 AS now_ts


![](linux-support-portfolio/08-evidence/screenshots/Screenshot_2026-10-27_19-07-02.png)



![](../08-evidence/screenshots/Screenshot_2026-10-27_19-07-02%202.png)