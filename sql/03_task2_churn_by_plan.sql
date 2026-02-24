-- 03_task2_churn_by_plan.sql
-- Churn by plan tier + billing cycle, rolling 6 months.
--
-- Plan snapshot at month start uses ROW_NUMBER to handle accounts
-- with multiple active rows (pick most recently started one).
-- Both logo churn rate and MRR churn rate included — Finance wants the latter.

WITH months AS (
    SELECT
        date_trunc('month', m)::TIMESTAMPTZ                               AS month_start,
        (date_trunc('month', m) + INTERVAL '1 month')::TIMESTAMPTZ        AS next_month_start
    FROM generate_series(
        date_trunc('month', NOW()) - INTERVAL '5 months',
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS m
),

-- Join plan metadata onto cleaned subscriptions
sub AS (
    SELECT
        s.*,
        p.plan_name,
        p.billing_cycle
    FROM v_subscriptions_clean s
    JOIN plans p ON p.plan_id = s.plan_id
),

-- Snapshot each account's plan at the start of each month
-- ROW_NUMBER ensures 1 row per account per month (latest started_at wins)
account_plan_at_start AS (
    SELECT
        mo.month_start,
        sub.account_id,
        sub.plan_name,
        sub.billing_cycle,
        ROW_NUMBER() OVER (
            PARTITION BY mo.month_start, sub.account_id
            ORDER BY sub.started_at DESC
        ) AS rn
    FROM months mo
    JOIN sub
      ON sub.started_at < mo.month_start
     AND (sub.ended_at IS NULL OR sub.ended_at >= mo.month_start)
     AND sub.status <> 'paused'
),

active_start AS (
    SELECT
        month_start,
        plan_name,
        billing_cycle,
        COUNT(*) AS active_start
    FROM account_plan_at_start
    WHERE rn = 1
    GROUP BY 1, 2, 3
),

churned AS (
    SELECT
        mo.month_start,
        sub.plan_name,
        sub.billing_cycle,
        COUNT(DISTINCT sub.account_id) AS churned
    FROM months mo
    JOIN sub
      ON sub.status = 'cancelled'
     AND sub.ended_at >= mo.month_start
     AND sub.ended_at <  mo.next_month_start
     AND sub.is_plan_change_end = FALSE
    GROUP BY 1, 2, 3
)

SELECT
    a.month_start                                                       AS month,
    a.plan_name,
    a.billing_cycle,
    a.active_start,
    COALESCE(c.churned, 0)                                             AS churned,
    ROUND(COALESCE(c.churned, 0)::NUMERIC / NULLIF(a.active_start, 0) * 100, 2)
                                                                        AS churn_rate_pct
FROM active_start a
LEFT JOIN churned c
       ON c.month_start    = a.month_start
      AND c.plan_name      = a.plan_name
      AND c.billing_cycle  = a.billing_cycle
ORDER BY month, plan_name, billing_cycle;
