# saas-churn-plan-change-analysis

Subscription churn pipeline that separates true cancellations from plan changes, dedupes at the account level, and reports churn by plan tier. Built in SQL + dbt with automated tests.

---

## The Problem

The billing system records a plan upgrade as two events: a cancellation on the old plan, then a new subscription starting at the exact same timestamp. A naive churn query counts that cancellation — which means every upgrade inflates the churn rate.

This pipeline detects plan changes via exact timestamp match and excludes them. It also counts by `account_id` so multi-seat accounts don't get double-counted, and strips test/demo accounts from all outputs.

In this dataset, **37.5% of all cancelled rows were plan changes** — not true churn. Excluding them corrects the churn rate by ~0.4–0.8 pts depending on the month.

---

## Outputs

| Model | Description | Window |
|---|---|---|
| `mart_monthly_churn` | Monthly churn rate trend | Rolling 12 months |
| `mart_churn_by_plan` | Churn by plan tier + billing cycle | Rolling 6 months |
| `mart_first_vs_rechurn` | First-time vs. returning churners | Rolling 12 months |
| `mart_subscription_overlaps` | Overlapping subscriptions (data quality) | All time |

---

## Sample Output

**Monthly churn — last 12 months**

| Month | Active at Start | True Churned | Churn Rate |
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

**Churn by segment — Feb 2026**

| Plan | Billing | Active | Churned | Churn Rate |
|---|---|---|---|---|
| Enterprise | monthly | 73 | 2 | 2.74% |
| Growth | monthly | 107 | 1 | 0.93% |
| Starter | annual | 63 | 1 | 1.59% |
| Enterprise | annual | 74 | 0 | 0.00% |
| Growth | annual | 72 | 0 | 0.00% |
| Starter | monthly | 71 | 0 | 0.00% |

**Validation checks**

| Check | Result |
|---|---|
| Plan-change contamination | 30 of 80 cancelled rows (37.5%) |
| Test/Demo leakage | 0 rows — PASS |
| Subscription overlaps | 0 pairs — PASS |
| Churn rate anomalies (>15%) | 0 months — PASS |
| Cancelled rows missing `ended_at` | 0 — PASS |

---

## Churn Definition

A subscription counts as true churn when:
- `status = 'cancelled'` and `ended_at` falls within the reporting month
- No subscription for the same `account_id` starts at `ended_at` (plan change exclusion)
- Account is not TEST or DEMO
- Counted once per `account_id`

```
churn_rate = churned_accounts / active_accounts_at_month_start
```

Full definitions: [`docs/metric_definitions.md`](docs/metric_definitions.md)  
Assumptions and edge cases: [`docs/assumptions_and_traps.md`](docs/assumptions_and_traps.md)

---

## Repo Structure

```
saas-churn-plan-change-analysis/
├── sql/                        # Standalone Postgres SQL — runs without dbt
│   ├── 00_setup.sql            # Synthetic data generator for local dev
│   ├── 01_clean_base.sql       # Base view: test/demo exclusion + plan-change flag
│   ├── 02_task1_monthly_churn.sql
│   ├── 03_task2_churn_by_plan.sql
│   ├── 04_task3_first_vs_rechurn.sql
│   ├── 05_task4_overlaps.sql
│   └── 99_validation_checks.sql
├── dbt/
│   ├── models/
│   │   ├── staging/            # stg_accounts, stg_subscriptions, stg_plans
│   │   └── marts/              # four mart tables
│   ├── tests/                  # 3 custom tests
│   ├── macros/
│   ├── schema.yml              # built-in schema + relationship tests
│   └── profiles.yml.example
├── docs/
│   ├── metric_definitions.md
│   ├── assumptions_and_traps.md
│   └── analysis_findings.md
└── data/
    └── data_dictionary.md
```

---

## How to Run

**Standalone SQL**
```bash
docker run --name churn-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres
psql -U postgres -f sql/00_setup.sql
psql -U postgres -f sql/01_clean_base.sql
psql -U postgres -f sql/02_task1_monthly_churn.sql
# ... run 03–05, then:
psql -U postgres -f sql/99_validation_checks.sql
```

**dbt**
```bash
pip install dbt-postgres
cp dbt/profiles.yml.example ~/.dbt/profiles.yml  # fill in your connection
cd dbt
dbt run
dbt test
dbt docs generate && dbt docs serve
```

---

**Poojitha** · Senior Data Analyst  
[LinkedIn](#) · [Portfolio](#)
