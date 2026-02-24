-- stg_accounts.sql
-- Staging model: clean accounts with test/demo excluded
-- Materialized as VIEW (no storage cost, always fresh)

WITH source AS (
    SELECT * FROM {{ source('raw', 'accounts') }}
),

cleaned AS (
    SELECT
        account_id,
        company_name,
        created_at
    FROM source
    WHERE company_name NOT ILIKE '%test%'
      AND company_name NOT ILIKE '%demo%'
)

SELECT * FROM cleaned
