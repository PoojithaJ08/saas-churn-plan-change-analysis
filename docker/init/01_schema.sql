-- =============================================================
-- 01_schema.sql
-- Creates all tables. Runs automatically on first container start.
-- =============================================================

CREATE TABLE IF NOT EXISTS plans (
    plan_id       SERIAL PRIMARY KEY,
    plan_name     TEXT         NOT NULL,
    billing_cycle TEXT         NOT NULL CHECK (billing_cycle IN ('monthly', 'annual')),
    price_usd     NUMERIC(10,2)
);

CREATE TABLE IF NOT EXISTS accounts (
    account_id   SERIAL      PRIMARY KEY,
    company_name TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS subscriptions (
    subscription_id SERIAL      PRIMARY KEY,
    account_id      INT         NOT NULL REFERENCES accounts(account_id),
    plan_id         INT         NOT NULL REFERENCES plans(plan_id),
    status          TEXT        NOT NULL CHECK (status IN ('active', 'cancelled', 'paused')),
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_subscriptions_account_id  ON subscriptions(account_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status      ON subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_ended_at    ON subscriptions(ended_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_started_at  ON subscriptions(started_at);
