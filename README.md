# saas-churn-plan-change-analysis

Subscription churn pipeline that separates true cancellations from plan changes, dedupes at the account level, and reports churn by plan tier. Built in SQL + dbt with automated tests.

---

## Quickstart — one command

```bash
git clone https://github.com/PoojithaJ08/saas-churn-plan-change-analysis.git
cd saas-churn-plan-change-analysis
docker compose up -d
```

That's it. Docker will:
- Spin up a Postgres 15 database on `localhost:5432`
- Auto-create all tables
- Seed 500 accounts, 530 subscriptions (including 30 plan-change pairs)
- Create the `v_subscriptions_clean` view

**pgAdmin** (browser UI) available at [http://localhost:5050](http://localhost:5050)  
Login: `admin@churn.local` / `admin` — the database is pre-registered, no config needed.

**Connection details**
```
host:     localhost
port:     5432
database: churn_analytics
user:     churn_user
password: churn_pass
```

To stop: `docker compose down`  
To reset data: `docker compose down -v && docker compose up -d`

---

## Background

The billing system records a plan upgrade as two events: a cancellation on the old plan, then a new subscription starting at the exact same timestamp. Naive churn queries count that cancellation — so every upgrade inflates the churn rate.

This pipeline detects plan changes via timestamp match and excludes them. It also dedupes by `account_id` so multi-seat accounts count once, and strips test/demo accounts from all outputs.

In this dataset, **37.5% of cancelled rows were plan changes**, not true churn.

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
├── docker-compose.yml              # One command to spin up Postgres + pgAdmin
├── docker/
│   ├── init/
│   │   ├── 01_schema.sql           # Tables + indexes (auto-runs on first start)
│   │   └── 02_seed_data.sql        # Synthetic data + v_subscriptions_clean view
│   └── pgadmin_servers.json        # pgAdmin auto-registers the DB
├── sql/                            # Standalone SQL — runs against any Postgres
│   ├── 00_setup.sql
│   ├── 01_clean_base.sql
│   ├── 02_task1_monthly_churn.sql
│   ├── 03_task2_churn_by_plan.sql
│   ├── 04_task3_first_vs_rechurn.sql
│   ├── 05_task4_overlaps.sql
│   └── 99_validation_checks.sql
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   └── marts/
│   ├── tests/
│   ├── macros/
│   ├── schema.yml
│   └── profiles.yml.example        # Pre-filled with Docker credentials
├── notebooks/
│   └── churn_analysis.ipynb        # 4 charts, runs on seeded data
├── docs/
│   ├── metric_definitions.md
│   ├── assumptions_and_traps.md
│   └── analysis_findings.md
└── data/
    └── data_dictionary.md
```

---

## Running the full pipeline

**After `docker compose up -d`:**

```bash
# Option A — plain SQL
psql postgresql://churn_user:churn_pass@localhost:5432/churn_analytics \
  -f sql/02_task1_monthly_churn.sql

# Option B — dbt
cp dbt/profiles.yml.example ~/.dbt/profiles.yml
cd dbt
dbt run
dbt test
dbt docs generate && dbt docs serve
```

---

**Poojitha** · Senior Data Analyst  
[LinkedIn](#) · [Portfolio](#)
