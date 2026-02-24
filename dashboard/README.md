# Churn Analytics Dashboard

Live dashboard built with Streamlit. Connects directly to the Postgres database and refreshes every 5 minutes.

## Run locally

```bash
# 1. Make sure the DB is running
docker compose up -d

# 2. Install dependencies
pip install -r dashboard/requirements.txt

# 3. Launch
streamlit run dashboard/app.py
```

Opens at http://localhost:8501

Or with make:
```bash
make dashboard
```

## Deploy to Streamlit Cloud (free)

1. Push this repo to GitHub (already done)
2. Go to [share.streamlit.io](https://share.streamlit.io)
3. Connect your GitHub account
4. Select this repo, set main file to `dashboard/app.py`
5. Add secrets in the Streamlit Cloud UI:
   ```
   DB_HOST = your-db-host
   DB_NAME = churn_analytics
   DB_USER = churn_user
   DB_PASSWORD = churn_pass
   ```

## What's on the dashboard

- **4 KPI cards** — avg churn rate, active accounts, contamination %, peak month
- **Monthly churn trend** — bar chart + 3-month rolling average
- **Plan-change contamination** — donut showing what % of cancellations were NOT true churn
- **Churn by plan tier** — grouped bar, last 6 months
- **First churn vs re-churn** — donut split
- **Active account growth** — area chart, 12 months
- **Validation checks** — live PASS/WARN badges for all 5 data quality checks
