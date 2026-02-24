-- tests/assert_no_test_accounts.sql
-- Custom dbt test: verifies that TEST and DEMO accounts are fully excluded
-- from the stg_accounts model and all downstream marts.
-- This test must return 0 rows to pass.

SELECT
    a.account_id,
    a.company_name
FROM {{ source('public', 'accounts') }} a
WHERE (
    a.company_name ILIKE '%test%'
    OR a.company_name ILIKE '%demo%'
)
-- If any of these IDs appear in stg_accounts, the exclusion filter is broken
AND EXISTS (
    SELECT 1
    FROM {{ ref('stg_accounts') }} sa
    WHERE sa.account_id = a.account_id
)
