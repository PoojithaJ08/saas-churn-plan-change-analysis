-- =============================================================
-- 02_seed_data.sql
-- Seeds synthetic data. Runs automatically after 01_schema.sql
-- on first container start (docker-entrypoint-initdb.d).
--
-- 500 real accounts + 3 test/demo accounts
-- ~420 active, ~50 true cancellations, ~30 plan changes
-- Plan changes are the critical edge case: cancelled row where
-- a new subscription starts at exactly ended_at for the same account.
-- =============================================================

-- ─────────────────────────────────────────
-- Plans
-- ─────────────────────────────────────────
INSERT INTO plans (plan_name, billing_cycle, price_usd) VALUES
  ('Starter',    'monthly',  49.00),
  ('Starter',    'annual',   39.00),
  ('Growth',     'monthly', 149.00),
  ('Growth',     'annual',  119.00),
  ('Enterprise', 'monthly', 499.00),
  ('Enterprise', 'annual',  399.00);

-- ─────────────────────────────────────────
-- Accounts — 500 real + 3 test/demo
-- ─────────────────────────────────────────
INSERT INTO accounts (company_name, created_at)
SELECT
    'Company ' || gs,
    NOW() - (random() * INTERVAL '730 days')
FROM generate_series(1, 500) gs;

-- test/demo accounts — must be excluded from all analysis
INSERT INTO accounts (company_name, created_at) VALUES
  ('Test Account Alpha',  NOW() - INTERVAL '60 days'),
  ('Demo Corp',           NOW() - INTERVAL '45 days'),
  ('TESTING - Internal',  NOW() - INTERVAL '30 days');

-- ─────────────────────────────────────────
-- Subscriptions
-- ─────────────────────────────────────────

-- Active subscriptions
INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
SELECT
    a.account_id,
    (floor(random() * 6) + 1)::INT,
    'active',
    a.created_at,
    NULL
FROM accounts a
WHERE company_name NOT ILIKE '%test%'
  AND company_name NOT ILIKE '%demo%'
LIMIT 420;

-- True cancellations — no follow-on subscription, these ARE churn
INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
SELECT
    a.account_id,
    (floor(random() * 6) + 1)::INT,
    'cancelled',
    a.created_at,
    a.created_at + (random() * INTERVAL '300 days')
FROM accounts a
WHERE company_name NOT ILIKE '%test%'
  AND company_name NOT ILIKE '%demo%'
  AND a.account_id NOT IN (SELECT account_id FROM subscriptions)
LIMIT 50;

-- Plan changes — cancelled + immediately replaced at exact same timestamp
-- These look like churn but are NOT. This is what the pipeline must detect.
DO $$
DECLARE
  rec     RECORD;
  old_end TIMESTAMPTZ;
BEGIN
  FOR rec IN
    SELECT a.account_id
    FROM accounts a
    WHERE company_name NOT ILIKE '%test%'
      AND company_name NOT ILIKE '%demo%'
      AND a.account_id NOT IN (SELECT account_id FROM subscriptions)
    LIMIT 30
  LOOP
    old_end := NOW() - (random() * INTERVAL '200 days');

    -- old plan ends
    INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
    VALUES (rec.account_id, 1, 'cancelled', old_end - INTERVAL '90 days', old_end);

    -- new plan starts at exactly old_end — this is the plan-change signal
    INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
    VALUES (rec.account_id, 3, 'active', old_end, NULL);
  END LOOP;
END $$;

-- Test/demo subscriptions — must be excluded from all churn analysis
INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
SELECT
    a.account_id, 1, 'cancelled',
    NOW() - INTERVAL '30 days',
    NOW() - INTERVAL '5 days'
FROM accounts a
WHERE company_name ILIKE '%test%'
   OR company_name ILIKE '%demo%';

-- ─────────────────────────────────────────
-- Clean base view
-- ─────────────────────────────────────────
CREATE OR REPLACE VIEW v_subscriptions_clean AS
WITH clean_accounts AS (
    SELECT account_id FROM accounts
    WHERE company_name NOT ILIKE '%test%'
      AND company_name NOT ILIKE '%demo%'
),
base AS (
    SELECT s.* FROM subscriptions s
    INNER JOIN clean_accounts a USING (account_id)
)
SELECT
    b.*,
    EXISTS (
        SELECT 1 FROM subscriptions s2
        WHERE s2.account_id = b.account_id
          AND b.ended_at    IS NOT NULL
          AND s2.started_at = b.ended_at
    ) AS is_plan_change_end
FROM base b;

-- ─────────────────────────────────────────
-- Seed summary
-- ─────────────────────────────────────────
DO $$
DECLARE
  v_accounts      INT;
  v_subscriptions INT;
  v_plan_changes  INT;
  v_true_churns   INT;
BEGIN
  SELECT COUNT(*) INTO v_accounts      FROM accounts;
  SELECT COUNT(*) INTO v_subscriptions FROM subscriptions;
  SELECT COUNT(*) INTO v_plan_changes  FROM v_subscriptions_clean WHERE status='cancelled' AND is_plan_change_end=TRUE;
  SELECT COUNT(*) INTO v_true_churns   FROM v_subscriptions_clean WHERE status='cancelled' AND is_plan_change_end=FALSE;

  RAISE NOTICE '========================================';
  RAISE NOTICE 'Seed complete.';
  RAISE NOTICE '  Accounts:        %', v_accounts;
  RAISE NOTICE '  Subscriptions:   %', v_subscriptions;
  RAISE NOTICE '  True churns:     %', v_true_churns;
  RAISE NOTICE '  Plan changes:    %  (excluded from churn)', v_plan_changes;
  RAISE NOTICE '========================================';
END $$;
