-- 04_task3_first_vs_rechurn.sql
-- First-churn vs. re-churn, rolling 12 months.
--
-- Re-churners (seq > 1) were previously lost, came back, and left again.
-- They behave differently in win-back campaigns than first-timers —
-- different messaging, different conversion rate, different team ownership.
-- Worth segmenting before throwing everyone into the same retention flow.

WITH all_churns AS (
    -- All true cancellations ever, ordered per account
    SELECT
        account_id,
        ended_at,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY ended_at ASC
        ) AS churn_seq
    FROM v_subscriptions_clean
    WHERE status              = 'cancelled'
      AND ended_at            IS NOT NULL
      AND is_plan_change_end  = FALSE
),

-- Filter to the rolling 12-month window
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
    END                             AS churn_type,
    COUNT(DISTINCT account_id)      AS total_accounts,
    MIN(ended_at)                   AS earliest_churn_date,
    MAX(ended_at)                   AS latest_churn_date
FROM l12
GROUP BY 1
ORDER BY 1;
