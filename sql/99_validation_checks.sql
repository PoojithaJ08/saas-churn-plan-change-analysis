-- 99_validation_checks.sql
-- Run after every pipeline refresh. Each check should return 0 or a clearly
-- bounded result. Anything unexpected = stop, investigate before publishing.

-- ─────────────────────────────────────────────────────────────
-- 1. Plan-change contamination
-- How many "cancelled" rows are actually plan changes?
-- Baseline ~15-20%. If this spikes, timestamp matching may be broken.
-- ─────────────────────────────────────────────────────────────
SELECT
    '1. Plan-change contamination'                              AS check_name,
    COUNT(*) FILTER (WHERE status = 'cancelled')               AS total_cancelled,
    COUNT(*) FILTER (WHERE status = 'cancelled'
                      AND is_plan_change_end = TRUE)            AS plan_change_rows,
    COUNT(*) FILTER (WHERE status = 'cancelled'
                      AND is_plan_change_end = FALSE)           AS true_churn_rows,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'cancelled'
                          AND is_plan_change_end = TRUE)::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE status = 'cancelled'), 0) * 100,
    2)                                                          AS pct_false_churn
FROM v_subscriptions_clean;

-- ─────────────────────────────────────────────────────────────
-- 2. Test/Demo leakage — must return 0 rows
-- ─────────────────────────────────────────────────────────────
SELECT
    '2. Test/Demo leakage'          AS check_name,
    COUNT(*)                        AS leakage_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL — test accounts found in clean view'
    END                             AS result
FROM v_subscriptions_clean s
JOIN accounts a USING (account_id)
WHERE a.company_name ILIKE '%test%'
   OR a.company_name ILIKE '%demo%';

-- ─────────────────────────────────────────────────────────────
-- 3. Subscription overlaps — ideally 0, non-zero = upstream pipeline issue
-- ─────────────────────────────────────────────────────────────
SELECT
    '3. Subscription overlaps'      AS check_name,
    COUNT(*)                        AS overlap_pair_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARN — overlapping subscriptions detected'
    END                             AS result
FROM (
    SELECT 1
    FROM v_subscriptions_clean s1
    JOIN v_subscriptions_clean s2
      ON s1.account_id      = s2.account_id
     AND s1.subscription_id < s2.subscription_id
    WHERE s1.started_at < COALESCE(s2.ended_at, NOW())
      AND s2.started_at < COALESCE(s1.ended_at, NOW())
      AND GREATEST(s1.started_at, s2.started_at)
        < LEAST(COALESCE(s1.ended_at, NOW()), COALESCE(s2.ended_at, NOW()))
) x;

-- ─────────────────────────────────────────────────────────────
-- 4. Churn rate anomalies — flag anything > 15%, likely a data error
-- ─────────────────────────────────────────────────────────────
WITH months AS (
    SELECT
        date_trunc('month', m)::TIMESTAMPTZ                    AS month_start,
        (date_trunc('month', m) + INTERVAL '1 month')::TIMESTAMPTZ AS next_month_start
    FROM generate_series(
        date_trunc('month', NOW()) - INTERVAL '11 months',
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS m
),
monthly AS (
    SELECT
        mo.month_start,
        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.started_at < mo.month_start
              AND (s.ended_at IS NULL OR s.ended_at >= mo.month_start)
              AND s.status <> 'paused'
        ) AS active_start,
        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.status = 'cancelled'
              AND s.ended_at >= mo.month_start
              AND s.ended_at < mo.next_month_start
              AND s.is_plan_change_end = FALSE
        ) AS churned
    FROM months mo
    CROSS JOIN v_subscriptions_clean s
    GROUP BY 1
)
SELECT
    '4. Monthly churn rate anomalies'   AS check_name,
    month_start,
    active_start,
    churned,
    ROUND(churned::NUMERIC / NULLIF(active_start, 0) * 100, 2) AS churn_rate_pct,
    CASE
        WHEN churned::NUMERIC / NULLIF(active_start, 0) > 0.15
        THEN 'WARN — churn rate > 15%, investigate'
        ELSE 'PASS'
    END AS result
FROM monthly
WHERE churned > 0
ORDER BY month_start;

-- ─────────────────────────────────────────────────────────────
-- 5. Orphan accounts (no subscriptions) — INFO only, won't break metrics
--    but worth knowing if accounts table has junk rows
-- ─────────────────────────────────────────────────────────────
SELECT
    '5. Orphan accounts (no subscriptions)' AS check_name,
    COUNT(*)                                AS orphan_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'INFO — accounts exist with no subscription rows'
    END                                     AS result
FROM accounts a
WHERE NOT EXISTS (
    SELECT 1 FROM subscriptions s WHERE s.account_id = a.account_id
)
  AND a.company_name NOT ILIKE '%test%'
  AND a.company_name NOT ILIKE '%demo%';

-- ─────────────────────────────────────────────────────────────
-- 6. Cancelled rows missing ended_at — these silently fall out of churn counts
-- ─────────────────────────────────────────────────────────────
SELECT
    '6. Cancelled rows missing ended_at'    AS check_name,
    COUNT(*)                                AS null_ended_at_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL — cancelled rows with NULL ended_at found'
    END                                     AS result
FROM v_subscriptions_clean
WHERE status = 'cancelled'
  AND ended_at IS NULL;
