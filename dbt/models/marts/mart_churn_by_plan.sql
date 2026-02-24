-- mart_churn_by_plan.sql
-- Churn rate by plan tier and billing cycle — rolling 6 months

{{ config(materialized='table') }}

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

sub AS (
    SELECT
        s.*,
        p.plan_name,
        p.billing_cycle,
        p.price_usd
    FROM {{ ref('stg_subscriptions') }} s
    JOIN {{ ref('stg_plans') }} p ON p.plan_id = s.plan_id
),

account_plan_at_start AS (
    SELECT
        mo.month_start,
        sub.account_id,
        sub.plan_name,
        sub.billing_cycle,
        sub.price_usd,
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
        COUNT(*)                AS active_start,
        SUM(price_usd)          AS mrr_at_start    -- MRR at risk
    FROM account_plan_at_start
    WHERE rn = 1
    GROUP BY 1, 2, 3
),

churned AS (
    SELECT
        mo.month_start,
        sub.plan_name,
        sub.billing_cycle,
        COUNT(DISTINCT sub.account_id)  AS churned,
        SUM(sub.price_usd)              AS churned_mrr    -- $ value of churn
    FROM months mo
    JOIN sub
      ON sub.status = 'cancelled'
     AND sub.ended_at >= mo.month_start
     AND sub.ended_at <  mo.next_month_start
     AND sub.is_plan_change_end = FALSE
    GROUP BY 1, 2, 3
)

SELECT
    a.month_start                                                   AS month,
    a.plan_name,
    a.billing_cycle,
    a.active_start,
    a.mrr_at_start,
    COALESCE(c.churned, 0)                                         AS churned,
    COALESCE(c.churned_mrr, 0)                                     AS churned_mrr,
    ROUND(COALESCE(c.churned, 0)::NUMERIC
        / NULLIF(a.active_start, 0) * 100, 2)                     AS logo_churn_rate_pct,
    ROUND(COALESCE(c.churned_mrr, 0)
        / NULLIF(a.mrr_at_start, 0) * 100, 2)                     AS mrr_churn_rate_pct
FROM active_start a
LEFT JOIN churned c
       ON c.month_start   = a.month_start
      AND c.plan_name     = a.plan_name
      AND c.billing_cycle = a.billing_cycle
ORDER BY month, plan_name, billing_cycle
