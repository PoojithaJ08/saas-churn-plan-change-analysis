-- assert_no_plan_change_in_churn.sql
-- Verifies the mart_monthly_churn churned count matches a direct count
-- from stg_subscriptions filtering is_plan_change_end = FALSE.
-- Any discrepancy means plan-change rows leaked into the churn total.
-- Must return 0 rows to pass.

WITH direct_count AS (
    SELECT
        date_trunc('month', ended_at)::TIMESTAMPTZ AS cohort_month,
        COUNT(DISTINCT account_id)                  AS expected_churned
    FROM {{ ref('stg_subscriptions') }}
    WHERE status             = 'cancelled'
      AND is_plan_change_end = FALSE
      AND ended_at           IS NOT NULL
    GROUP BY 1
),

mart_count AS (
    SELECT cohort_month, churned AS mart_churned
    FROM {{ ref('mart_monthly_churn') }}
)

-- Return rows where the mart count doesn't match the direct count
-- An empty result = test passes
SELECT
    d.cohort_month,
    d.expected_churned,
    m.mart_churned
FROM direct_count d
JOIN mart_count m ON m.cohort_month = d.cohort_month
WHERE d.expected_churned <> m.mart_churned
