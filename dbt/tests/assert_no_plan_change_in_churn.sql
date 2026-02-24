-- tests/assert_no_plan_change_in_churn.sql
-- Custom dbt test: verifies that no plan-change rows leak into mart_monthly_churn.
-- This test must return 0 rows to pass.
--
-- Logic: joins mart_monthly_churn cohort months back to stg_subscriptions
-- and checks that no cancelled rows with is_plan_change_end = TRUE
-- are counted in the churned total.

WITH suspect_rows AS (
    SELECT
        s.subscription_id,
        s.account_id,
        s.ended_at,
        s.is_plan_change_end
    FROM {{ ref('stg_subscriptions') }} s
    WHERE s.status = 'cancelled'
      AND s.is_plan_change_end = TRUE
      AND s.ended_at IS NOT NULL
      -- If this account appears as churned in the mart for the same month,
      -- something is wrong with the plan-change exclusion logic
      AND EXISTS (
          SELECT 1
          FROM {{ ref('mart_monthly_churn') }} mc
          WHERE date_trunc('month', s.ended_at) = mc.cohort_month
            AND mc.churned > 0
      )
)

-- Returning any rows = TEST FAIL
-- The mart should never include plan-change cancellations in churn counts
SELECT *
FROM suspect_rows
WHERE is_plan_change_end = TRUE
