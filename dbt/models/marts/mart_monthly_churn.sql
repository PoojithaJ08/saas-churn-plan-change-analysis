-- mart_monthly_churn.sql
-- Monthly churn trend — rolling 12 months
-- Materialized as TABLE for dashboard performance

{{ config(materialized='table') }}

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
    CROSS JOIN {{ ref('stg_subscriptions') }} s
    GROUP BY 1
)

SELECT
    cohort_month,
    active_start,
    churned,
    ROUND(churned::NUMERIC / NULLIF(active_start, 0) * 100, 2) AS churn_rate_pct,
    -- Running average for trend smoothing
    ROUND(AVG(churned::NUMERIC / NULLIF(active_start, 0) * 100) OVER (
        ORDER BY cohort_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS churn_rate_3mo_avg
FROM monthly
ORDER BY cohort_month
