-- 02_task1_monthly_churn.sql
-- Monthly churn rate, rolling 12 months.
--
-- Denominator: active at month start = started before month, not ended before month, not paused
-- Numerator: cancelled within month, is_plan_change_end = FALSE
-- Grain: 1 row per month, DISTINCT account_id (not seats)

WITH months AS (
    SELECT
        date_trunc('month', m)::TIMESTAMPTZ                               AS month_start,
        (date_trunc('month', m) + INTERVAL '1 month')::TIMESTAMPTZ        AS next_month_start
    FROM generate_series(
        date_trunc('month', NOW()) - INTERVAL '11 months',
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS m
),

monthly AS (
    SELECT
        mo.month_start AS cohort_month,

        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.started_at < mo.month_start
              AND (s.ended_at IS NULL OR s.ended_at >= mo.month_start)
              AND s.status <> 'paused'
        ) AS active_start,

        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.status = 'cancelled'
              AND s.ended_at >= mo.month_start
              AND s.ended_at <  mo.next_month_start
              AND s.is_plan_change_end = FALSE
        ) AS churned

    FROM months mo
    CROSS JOIN v_subscriptions_clean s
    GROUP BY 1
)

SELECT
    cohort_month,
    active_start,
    churned,
    ROUND(churned::NUMERIC / NULLIF(active_start, 0) * 100, 2) AS churn_rate_pct
FROM monthly
ORDER BY cohort_month;
