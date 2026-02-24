# Assumptions & Traps

Non-obvious decisions in the pipeline and why they were made. Read this before changing the plan-change logic or the denominator definition.

---

## Assumption 1: Plan Change = Exact Timestamp Match

The billing system records upgrades as one atomic transaction — old plan ends, new plan starts at the same millisecond. The pipeline detects this via exact match between `ended_at` and `started_at`.

**Risk:** If the billing system has clock drift or batch-processing delays, a real plan change might show a small gap and get miscounted as true churn. This would over-count churn.

**If this happens:** Check `99_validation_checks.sql` Check 1. If `pct_false_churn` shifts significantly from baseline, look at timestamp precision in the source system. A tolerance window like `s2.started_at BETWEEN b.ended_at AND b.ended_at + INTERVAL '1 hour'` is a reasonable fix if drift is confirmed — document it here before changing.

---

## Assumption 2: Account = Customer

`account_id` is the customer grain. One account counts once, regardless of seats. This is the right default for "how many customers did we lose?" — which is different from "how many subscription rows were cancelled?"

**Risk:** If a company has multiple accounts (e.g., different divisions), this undercounts the business relationship. If churned customers create new accounts instead of reactivating, re-churn gets undercounted.

**If this matters:** A `parent_account_id` column solves this cleanly. Ask data engineering.

---

## Assumption 3: Paused Accounts Out of Denominator

Paused = intentionally suspended, not at standard churn risk, not generating MRR pressure. Including them inflates the denominator and makes churn look lower than it is.

**If Finance defines paused differently** (e.g., still billed): add `status = 'paused'` back to the active filter. One line change in `stg_subscriptions`.

---

## Assumption 4: Test/Demo Exclusion by Name Pattern

There's no `is_internal` flag in the source data, so exclusion relies on `ILIKE '%test%'` and `ILIKE '%demo%'`. This will miss accounts named `QA Corp`, `Sandbox`, `Internal`, etc.

**Mitigation:** Request a proper boolean flag from engineering. Until then, run Check 2 in `99_validation_checks.sql` and do a periodic spot-check on account names with the CS team.

---

## Assumption 5: Cancelled Rows Have Non-NULL ended_at

The churn calculation assigns cancellations to months via `ended_at`. A NULL on a cancelled row silently drops that account from churn counts.

Check 6 in `99_validation_checks.sql` catches this. There is no `not_null` test on `ended_at` in schema.yml because active subscriptions legitimately have NULL `ended_at` — the validation check handles the cancelled-specific case.

---

## Performance Note: CROSS JOIN

`mart_monthly_churn` uses `CROSS JOIN` between months and subscriptions. This is intentional — every subscription needs evaluation against every month. Fine up to ~5M rows. Beyond that, partition subscriptions by year/month before the join, or use dbt's `date_spine` macro.

---

## Note: NOW() Anchors

All month-series CTEs use `NOW()` so the pipeline is always relative to today. If you need a static snapshot (e.g., "churn as of Q3 close"), replace `NOW()` with `'2024-10-01'::timestamptz`.

