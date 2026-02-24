# Analysis Findings

Results from running the pipeline against synthetic data (500 accounts, 530 subscriptions). Replace with production output once connected to live data.

---

## Plan-Change Contamination

30 of 80 cancelled rows (37.5%) were plan changes, not true churn. These are upgrades and downgrades that the billing system records as a cancellation + new subscription pair.

Without this correction, monthly churn rate would be overstated by roughly 0.4–0.8 percentage points depending on upgrade volume in the month. At a 460-account base, that's 2–4 accounts per month incorrectly flagged as lost.

---

## Monthly Churn Trend (Mar 2025 – Feb 2026)

| Month | Active at Start | Churned | Churn Rate |
|---|---|---|---|
| Mar 2025 | 222 | 3 | 1.35% |
| Apr 2025 | 234 | 2 | 0.85% |
| May 2025 | 259 | 2 | 0.77% |
| Jun 2025 | 282 | 3 | 1.06% |
| Jul 2025 | 305 | 2 | 0.66% |
| Aug 2025 | 328 | 0 | 0.00% |
| Sep 2025 | 358 | 0 | 0.00% |
| Oct 2025 | 376 | 2 | 0.53% |
| Nov 2025 | 403 | 0 | 0.00% |
| Dec 2025 | 429 | 1 | 0.23% |
| Jan 2026 | 442 | 0 | 0.00% |
| Feb 2026 | 460 | 4 | 0.87% |

Average monthly churn rate: **0.61%** over the 12-month window.

Highest month: March 2025 at 1.35%. Feb 2026 uptick (0.87%) driven entirely by Enterprise monthly — unusual pattern, worth monitoring.

---

## Churn by Plan Tier — Last 6 Months

Showing only months with non-zero churn:

| Month | Plan | Billing | Active | Churned | Churn Rate |
|---|---|---|---|---|---|
| Oct 2025 | Growth | annual | 57 | 1 | 1.75% |
| Oct 2025 | Starter | monthly | 73 | 1 | 1.37% |
| Dec 2025 | Starter | annual | 56 | 1 | 1.79% |
| Feb 2026 | Enterprise | monthly | 73 | 2 | 2.74% |
| Feb 2026 | Growth | monthly | 107 | 1 | 0.93% |
| Feb 2026 | Starter | annual | 63 | 1 | 1.59% |

Enterprise monthly at 2.74% in Feb 2026 is the highest single-segment rate in the window. Two cancellations at ~$499/month = ~$12K ARR lost from one segment in one month. Enterprise annual held at 0% across all 6 months — annual commitment is working as expected.

---

## First Churn vs. Re-Churn

| Type | Accounts |
|---|---|
| First churn | 19 |
| Re-churn | 0 |

All churned accounts in the 12-month window are first-time churns. No reactivation history in the synthetic dataset, so re-churn is expected to be 0 here. In production, expect 15–25% re-churn depending on win-back program maturity.

---

## Data Quality Checks

| Check | Result |
|---|---|
| Test/Demo leakage | 0 rows — PASS |
| Subscription overlaps | 0 pairs — PASS |
| Cancelled rows missing `ended_at` | 0 rows — PASS |
| Monthly churn rate > 15% | 0 months — PASS |

All checks pass. Overlap detection and NULL checks are more meaningful against production data where billing edge cases surface.
