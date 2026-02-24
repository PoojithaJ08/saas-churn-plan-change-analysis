-- tests/assert_churn_rate_reasonable.sql
-- Custom dbt test: flags any month where churn rate exceeds 15%.
-- Values above 15% almost always indicate a data error rather than
-- real business churn. This test must return 0 rows to pass.
--
-- To adjust the threshold, change the 15 below.

SELECT
    cohort_month,
    active_start,
    churned,
    churn_rate_pct
FROM {{ ref('mart_monthly_churn') }}
WHERE churn_rate_pct > 15
  AND active_start   > 10    -- ignore months with too-small denominators
