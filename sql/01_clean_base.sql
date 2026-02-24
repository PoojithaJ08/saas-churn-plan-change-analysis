-- 01_clean_base.sql
-- Base view used by all downstream queries.
-- Does two things: strips test/demo accounts, flags plan-change endings.
--
-- Plan-change detection: billing system writes cancellation + new subscription
-- in the same transaction, so ended_at on old == started_at on new exactly.
-- Anything matching that pattern is NOT churn.

CREATE OR REPLACE VIEW v_subscriptions_clean AS

WITH clean_accounts AS (
    SELECT account_id
    FROM accounts
    WHERE company_name NOT ILIKE '%test%'
      AND company_name NOT ILIKE '%demo%'
),

base AS (
    SELECT s.*
    FROM subscriptions s
    INNER JOIN clean_accounts a USING (account_id)
)

SELECT
    b.*,
    EXISTS (
        SELECT 1
        FROM subscriptions s2
        WHERE s2.account_id = b.account_id
          AND b.ended_at    IS NOT NULL
          AND s2.started_at = b.ended_at
    ) AS is_plan_change_end

FROM base b;

-- sanity check
SELECT
    COUNT(*)                                                    AS total_rows,
    COUNT(*) FILTER (WHERE status = 'cancelled')                AS cancelled_rows,
    COUNT(*) FILTER (WHERE status = 'cancelled'
                       AND is_plan_change_end = TRUE)           AS plan_change_rows,
    COUNT(*) FILTER (WHERE status = 'cancelled'
                       AND is_plan_change_end = FALSE)          AS true_churn_rows
FROM v_subscriptions_clean;
