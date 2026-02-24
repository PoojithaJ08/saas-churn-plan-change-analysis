# Data Dictionary

## Table: `accounts`

| Column | Type | Description |
|---|---|---|
| `account_id` | UUID / BIGINT | Primary key. One row per customer account. |
| `company_name` | TEXT | Customer company name. Rows containing `test` or `demo` (case-insensitive) are excluded from all analysis. |
| `created_at` | TIMESTAMPTZ | Account creation timestamp. |
| `tier` | TEXT | Account tier at signup (`starter`, `growth`, `enterprise`). Plan-level tier is pulled from the `plans` table for subscription-level analysis. |

---

## Table: `subscriptions`

| Column | Type | Description |
|---|---|---|
| `subscription_id` | UUID / BIGINT | Primary key. One row per subscription lifecycle. |
| `account_id` | UUID / BIGINT | FK → `accounts`. An account may have more than one row (plan changes, reactivations). |
| `plan_id` | UUID / BIGINT | FK → `plans`. The plan active for this subscription. |
| `status` | TEXT | `active`, `cancelled`, `paused`. Only `cancelled` rows are evaluated for churn. |
| `started_at` | TIMESTAMPTZ | When the subscription became active. |
| `ended_at` | TIMESTAMPTZ | When the subscription ended (NULL if still active). |

**Key derived flag:** `is_plan_change_end` (added in `stg_subscriptions`)

```
TRUE when: status = 'cancelled'
       AND there exists another subscription for the same account_id
           where s2.started_at = s1.ended_at
```

If `is_plan_change_end = TRUE`, the cancellation is **excluded from churn** — the customer is still active, just on a different plan.

---

## Table: `plans`

| Column | Type | Description |
|---|---|---|
| `plan_id` | UUID / BIGINT | Primary key. |
| `plan_name` | TEXT | Human-readable plan name (e.g., `Starter`, `Growth`, `Enterprise`). |
| `billing_cycle` | TEXT | `monthly` or `annual`. |
| `price_usd` | NUMERIC | Monthly price in USD. Used for MRR churn calculations (optional). |

---

## Derived / Mart Tables

| Table | Grain | Description |
|---|---|---|
| `stg_subscriptions` | 1 row per subscription | Cleaned, test/demo excluded, `is_plan_change_end` flagged |
| `stg_accounts` | 1 row per account | Cleaned, test/demo excluded |
| `stg_plans` | 1 row per plan | Plan metadata |
| `mart_monthly_churn` | 1 row per month | Active count, churned count, churn rate % — 12-month rolling |
| `mart_churn_by_plan` | 1 row per month × plan × billing cycle | Churn rate broken out by plan tier — 6-month rolling |
| `mart_first_vs_rechurn` | 1 row per churn_type | First-time churners vs. returning churners — 12-month rolling |
| `mart_subscription_overlaps` | 1 row per overlapping pair | Data quality: subscriptions for the same account with overlapping dates |
