-- stg_plans.sql
-- Staging model: plan reference data (no filtering needed)

WITH source AS (
    SELECT * FROM {{ source('public', 'plans') }}
)

SELECT
    plan_id,
    plan_name,
    billing_cycle,
    price_usd
FROM source
