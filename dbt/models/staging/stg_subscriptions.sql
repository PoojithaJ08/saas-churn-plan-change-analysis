-- stg_subscriptions.sql
-- Staging model: subscriptions joined to clean accounts
-- with is_plan_change_end flag computed here for all downstream use.
--
-- Key business rule implemented:
--   is_plan_change_end = TRUE when a cancellation is immediately
--   followed by a new subscription for the same account (plan change),
--   meaning this row should NOT count as true churn.

WITH source AS (
    SELECT * FROM {{ source('public', 'subscriptions') }}
),

clean_accounts AS (
    SELECT account_id FROM {{ ref('stg_accounts') }}
),

base AS (
    SELECT s.*
    FROM source s
    INNER JOIN clean_accounts a USING (account_id)
),

final AS (
    SELECT
        b.subscription_id,
        b.account_id,
        b.plan_id,
        b.status,
        b.started_at,
        b.ended_at,
        -- Plan-change flag: cancellation immediately replaced by new subscription
        EXISTS (
            SELECT 1
            FROM source s2
            WHERE s2.account_id = b.account_id
              AND b.ended_at    IS NOT NULL
              AND s2.started_at = b.ended_at
        ) AS is_plan_change_end
    FROM base b
)

SELECT * FROM final
