-- mart_first_vs_rechurn.sql
-- First-churn vs. re-churn segmentation — rolling 12 months

{{ config(materialized='table') }}

WITH all_churns AS (
    SELECT
        account_id,
        ended_at,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY ended_at ASC
        ) AS churn_seq
    FROM {{ ref('stg_subscriptions') }}
    WHERE status             = 'cancelled'
      AND ended_at           IS NOT NULL
      AND is_plan_change_end = FALSE
),

l12 AS (
    SELECT *
    FROM all_churns
    WHERE ended_at >= date_trunc('month', NOW()) - INTERVAL '11 months'
      AND ended_at <  date_trunc('month', NOW()) + INTERVAL '1 month'
)

SELECT
    CASE
        WHEN churn_seq = 1 THEN 'first_churn'
        ELSE                    're_churn'
    END                                                 AS churn_type,
    COUNT(DISTINCT account_id)                          AS total_accounts,
    ROUND(COUNT(DISTINCT account_id)::NUMERIC
        / SUM(COUNT(DISTINCT account_id)) OVER () * 100, 1)
                                                        AS pct_of_total_churns
FROM l12
GROUP BY 1
ORDER BY 1
