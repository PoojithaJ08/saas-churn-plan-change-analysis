-- =============================================================
-- 00_setup.sql
-- Creates tables and loads synthetic data for local development.
-- Run this once before executing any other SQL files.
-- =============================================================

DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS plans CASCADE;

-- ─────────────────────────────────────────
-- Plans
-- ─────────────────────────────────────────
CREATE TABLE plans (
    plan_id       SERIAL PRIMARY KEY,
    plan_name     TEXT NOT NULL,
    billing_cycle TEXT NOT NULL CHECK (billing_cycle IN ('monthly','annual')),
    price_usd     NUMERIC(10,2)
);

INSERT INTO plans (plan_name, billing_cycle, price_usd) VALUES
  ('Starter',    'monthly',  49.00),
  ('Starter',    'annual',   39.00),
  ('Growth',     'monthly', 149.00),
  ('Growth',     'annual',  119.00),
  ('Enterprise', 'monthly', 499.00),
  ('Enterprise', 'annual',  399.00);

-- ─────────────────────────────────────────
-- Accounts
-- ─────────────────────────────────────────
CREATE TABLE accounts (
    account_id   SERIAL PRIMARY KEY,
    company_name TEXT NOT NULL,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Real customers
INSERT INTO accounts (company_name, created_at)
SELECT
    'Company ' || gs,
    NOW() - (random() * interval '730 days')
FROM generate_series(1, 500) gs;

-- Test / Demo accounts (should be excluded from all analysis)
INSERT INTO accounts (company_name, created_at) VALUES
  ('Test Account Alpha',  NOW() - interval '60 days'),
  ('Demo Corp',           NOW() - interval '45 days'),
  ('TESTING - Internal',  NOW() - interval '30 days');

-- ─────────────────────────────────────────
-- Subscriptions
-- ─────────────────────────────────────────
CREATE TABLE subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    account_id      INT  NOT NULL REFERENCES accounts(account_id),
    plan_id         INT  NOT NULL REFERENCES plans(plan_id),
    status          TEXT NOT NULL CHECK (status IN ('active','cancelled','paused')),
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ
);

-- Active subscriptions (most accounts)
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

-- True cancellations (no follow-on subscription)
INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
SELECT
    a.account_id,
    (floor(random() * 6) + 1)::INT,
    'cancelled',
    a.created_at,
    a.created_at + (random() * interval '300 days')
FROM accounts a
WHERE company_name NOT ILIKE '%test%'
  AND company_name NOT ILIKE '%demo%'
  AND a.account_id NOT IN (SELECT account_id FROM subscriptions)
LIMIT 50;

-- Plan changes: cancelled + immediately replaced (ended_at = new started_at)
-- This is the critical edge case the pipeline must handle correctly
DO $$
DECLARE
  rec RECORD;
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
    old_end := NOW() - (random() * interval '200 days');

    -- Old plan: cancelled
    INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
    VALUES (rec.account_id, 1, 'cancelled', old_end - interval '90 days', old_end);

    -- New plan: starts exactly at old_end (plan change!)
    INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
    VALUES (rec.account_id, 3, 'active', old_end, NULL);
  END LOOP;
END $$;

-- Test account subscriptions (must be excluded)
INSERT INTO subscriptions (account_id, plan_id, status, started_at, ended_at)
SELECT
    a.account_id, 1, 'cancelled',
    NOW() - interval '30 days', NOW() - interval '5 days'
FROM accounts a
WHERE company_name ILIKE '%test%' OR company_name ILIKE '%demo%';

SELECT 'Setup complete.' AS status,
       (SELECT COUNT(*) FROM accounts)      AS total_accounts,
       (SELECT COUNT(*) FROM subscriptions) AS total_subscriptions,
       (SELECT COUNT(*) FROM plans)         AS total_plans;
