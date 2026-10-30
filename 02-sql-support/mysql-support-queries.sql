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


-- 0.2 Row counts. If these don't match expectations, stop —
--     you're querying the wrong DB or a restored copy.
SELECT 'clients'        AS tbl, COUNT(*) AS rows_ FROM clients
UNION ALL SELECT 'users',        COUNT(*) FROM users
UNION ALL SELECT 'cases',        COUNT(*) FROM cases
UNION ALL SELECT 'transfers',    COUNT(*) FROM transfers
UNION ALL SELECT 'transfers_bulk', COUNT(*) FROM transfers_bulk;

-- 0.2 Row counts. If these don't match expectations, stop —
--     you're querying the wrong DB or a restored copy.
SELECT 'clients'        AS tbl, COUNT(*) AS rows_ FROM clients
UNION ALL SELECT 'users',        COUNT(*) FROM users
UNION ALL SELECT 'cases',        COUNT(*) FROM cases
UNION ALL SELECT 'transfers',    COUNT(*) FROM transfers
UNION ALL SELECT 'transfers_bulk', COUNT(*) FROM transfers_bulk;

-- -------------------------------------------------------------
-- 1. Open and overdue cases (ticket queue view)
-- 1.1 All open cases, oldest first. Oldest = most at risk.
SELECT
  c.case_id,
  cl.name              AS client,
  cl.tier,
  c.priority,
  c.category,
  c.opened_at,
  TIMESTAMPDIFF(HOUR, c.opened_at, NOW()) AS age_hours,
  c.subject
FROM cases c
JOIN clients cl ON cl.client_id = c.client_id
WHERE c.status = 'open'
ORDER BY c.opened_at ASC;

- 1.2 Overdue open cases. Threshold by priority is a business
--     rule; adjust per contract. This version: high > 24h,
--     medium > 72h, low > 168h.
SELECT
  c.case_id,
  cl.name              AS client,
  cl.tier,
  c.priority,
  c.opened_at,
  TIMESTAMPDIFF(HOUR, c.opened_at, NOW()) AS age_hours,
  CASE c.priority
    WHEN 'high'   THEN 24
    WHEN 'medium' THEN 72
    ELSE 168
  END                  AS sla_hours,
  c.subject
FROM cases c
JOIN clients cl ON cl.client_id = c.client_id
WHERE c.status = 'open'
  AND (
    (c.priority = 'high'   AND TIMESTAMPDIFF(HOUR, c.opened_at, NOW()) > 24)
    OR (c.priority = 'medium' AND TIMESTAMPDIFF(HOUR, c.opened_at, NOW()) > 72)
    OR (c.priority = 'low'    AND TIMESTAMPDIFF(HOUR, c.opened_at, NOW()) > 168)
  )
ORDER BY c.priority, c.opened_at ASC;

-- -------------------------------------------------------------
-- 3. Transfer triage

-- 3.3 Latest transfer per client.
--     MySQL 8 window function — replaces the old
--     correlated-subquery trick and is faster and clearer.

SELECT
  client_id,
  transfer_id,
  protocol,
  filename,
  status,
  error_code,
  started_at
FROM (
  SELECT
    t.*,
    ROW_NUMBER() OVER (
      PARTITION BY client_id
      ORDER BY started_at DESC
    ) AS rn
  FROM transfers t
) x
WHERE rn = 1
ORDER BY client_id;


-- 4.1 Locked or disabled users, by client.
--     This is the first query on any auth ticket.
SELECT
  u.user_id,
  cl.name              AS client,
  u.email,
  u.status,
  u.last_login
FROM users u
JOIN clients cl ON cl.client_id = u.client_id
WHERE u.status IN ('locked', 'disabled')
ORDER BY cl.name, u.email;


-- 4.3 Users who have never logged in (last_login IS NULL).
--     Distinct from "inactive" — these are likely provisioning
--     errors, not dormant accounts.
SELECT
  u.user_id,
  cl.name              AS client,
  u.email,
  u.status
FROM users u
JOIN clients cl ON cl.client_id = u.client_id
WHERE u.last_login IS NULL
ORDER BY cl.name, u.email;


- 7.1 Pattern: SELECT first.
--     Find the exact rows you intend to change.
SELECT user_id, email, status
FROM users
WHERE email = 'it@acme.com'
  AND status = 'locked';
















