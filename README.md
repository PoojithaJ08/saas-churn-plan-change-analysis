# saas-churn-plan-change-analysis

[![dbt CI](https://github.com/PoojithaJ08/saas-churn-plan-change-analysis/actions/workflows/dbt_ci.yml/badge.svg)](https://github.com/PoojithaJ08/saas-churn-plan-change-analysis/actions/workflows/dbt_ci.yml)

Subscription churn pipeline that separates true cancellations from plan changes, dedupes at the account level, and reports churn by plan tier. Built in SQL + dbt with automated tests.

---

## Quickstart — one command

```bash
git clone https://github.com/PoojithaJ08/saas-churn-plan-change-analysis.git
cd saas-churn-plan-change-analysis
docker compose up -d
```

Docker spins up Postgres 15 + pgAdmin, creates all tables, and seeds 500 accounts with realistic churn patterns including plan-change pairs.

**pgAdmin** at [http://localhost:5050](http://localhost:5050) — `admin@churn.local` / `admin`

```
host: localhost  port: 5432
db:   churn_analytics
user: churn_user  password: churn_pass
```

---

## Common commands

```bash
make up        # start DB + pgAdmin
make run       # dbt run
make test      # dbt test
make validate  # run 99_validation_checks.sql
make docs      # generate + serve dbt docs
make reset     # wipe data and reseed
make psql      # open psql shell
```

---

## The Problem

The billing system records a plan upgrade as two events: a cancellation on the old plan, then a new subscription starting at the exact same timestamp. A naive churn query counts that cancellation — so every upgrade inflates the churn rate.

This pipeline detects plan changes via exact timestamp match and excludes them. It also counts by `account_id` so multi-seat accounts don't inflate the count, and strips test/demo accounts from all outputs.

**In this dataset: 37.5% of cancelled rows were plan changes, not true churn.**

---

## Outputs

| Model | Description | Window |
|---|---|---|
| `mart_monthly_churn` | Monthly churn rate + 3-mo rolling avg | Rolling 12 months |
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
├── Makefile                        # make up / run / test / reset / docs
├── .github/workflows/dbt_ci.yml   # CI: runs dbt run + dbt test on every push
├── docker/
│   ├── init/
│   │   ├── 01_schema.sql           # Tables + indexes (auto-runs on first start)
│   │   └── 02_seed_data.sql        # Synthetic data + v_subscriptions_clean view
│   └── pgadmin_servers.json
├── sql/                            # Standalone SQL
│   ├── 00_setup.sql
│   ├── 01–05_*.sql
│   └── 99_validation_checks.sql
├── dbt/
│   ├── models/staging/             # stg_accounts, stg_subscriptions, stg_plans
│   ├── models/marts/               # 4 mart tables
│   ├── tests/                      # 3 custom data tests
│   ├── schema.yml
│   └── profiles.yml.example        # Pre-filled with Docker credentials
├── notebooks/
│   └── churn_analysis.ipynb        # 4 charts, live DB connection via psycopg2
├── docs/
│   ├── metric_definitions.md
│   ├── assumptions_and_traps.md
│   └── analysis_findings.md
└── data/
    └── data_dictionary.md
```

---

## Running dbt

```bash
# profiles.yml is pre-filled with Docker credentials — just copy it
cp dbt/profiles.yml.example ~/.dbt/profiles.yml
cd dbt
dbt run
dbt test
dbt docs generate && dbt docs serve
```

---

## Tech Stack

PostgreSQL 15 · dbt Core 1.7 · Docker Compose · Python 3.11 · GitHub Actions

---

**Poojitha** · Senior Data Analyst  
[LinkedIn](#) · [Portfolio](#)
