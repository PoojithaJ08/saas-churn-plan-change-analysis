# Metric Definitions

Definitions used in this pipeline. When a stakeholder questions a number, this is the reference doc.

---

## True Churn (Account-Level)

An account is **churned** in a given month when:

1. It has a subscription row with `status = 'cancelled'`
2. `ended_at` falls within the calendar month
3. `is_plan_change_end = FALSE` — no new subscription for the same account starts at `ended_at`
4. `company_name` doesn't contain `test` or `demo`
5. Counted once via `DISTINCT account_id` regardless of seat count

## Plan Change (Not Churn)

A cancellation where another subscription for the same `account_id` starts at the exact `ended_at` of the cancelled row. Customer is still active. `is_plan_change_end = TRUE`, excluded from all churn metrics.

## Active Account (Denominator)

Active at start of month M when:
- `started_at < month_start`
- `ended_at IS NULL` OR `ended_at >= month_start`
- `status <> 'paused'`

Paused accounts are out of the denominator. They haven't cancelled and they're not generating normal churn risk. If Finance defines paused differently (still billed), add them back — one line change in `stg_subscriptions`.

---

## Calculated Metrics

**Logo Churn Rate**
```
churned_accounts / active_accounts_at_month_start × 100
```
Counts customers. A single Enterprise account cancelling is the same weight as a Starter account.

**MRR Churn Rate**
```
churned_mrr / mrr_at_start × 100
```
Revenue-weighted. Available in `mart_churn_by_plan`. More relevant to Finance and executives because Enterprise churn has outsized ARR impact compared to logo count.

**First Churn vs. Re-Churn**
- `churn_seq = 1` → first ever cancellation for this account
- `churn_seq > 1` → account churned, came back, churned again

The two groups need different win-back approaches. Don't lump them together in a retention campaign.

**3-Month Rolling Average**
Smooths seasonal noise. Use for trend charts, not as a point-in-time metric.

---

## What This Pipeline Does Not Measure

| Metric | Why |
|---|---|
| Seat-level churn / contraction | Needs separate MRR contraction tracking |
| Involuntary churn (failed payments) | Needs payment failure status in source data |
| Net MRR churn | Requires expansion MRR data |
| Cohort retention curves | Different query shape — see notebooks/ |

---

## Exclusions

| What | Why |
|---|---|
| TEST/DEMO accounts | Internal activity contaminates cancellation counts |
| Paused accounts | Not at standard churn risk; track separately |
| Plan changes | Customer is still active; inflates churn if included |

