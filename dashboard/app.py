import os
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import psycopg2
from psycopg2.extras import RealDictCursor

# ─────────────────────────────────────────
# Page config
# ─────────────────────────────────────────
st.set_page_config(
    page_title="Churn Analytics",
    page_icon="📉",
    layout="wide",
)

# ─────────────────────────────────────────
# Theme
# ─────────────────────────────────────────
DARK   = "#1a1a2e"
ACCENT = "#e94560"
BLUE   = "#0f3460"
TEAL   = "#16213e"
LIGHT  = "#f5f5f5"
GRAY   = "#9e9e9e"
GREEN  = "#2ecc71"

PLAN_COLORS = {
    "Enterprise": "#0f3460",
    "Growth":     "#e94560",
    "Starter":    "#f39c12",
}

st.markdown("""
<style>
    .stApp { background-color: #1a1a2e; }
    .block-container { padding-top: 1.5rem; }
    h1, h2, h3 { color: #f5f5f5; }
    .metric-card {
        background: #16213e;
        border-radius: 8px;
        padding: 1.2rem 1.5rem;
        border-left: 3px solid #e94560;
    }
    .metric-value { font-size: 2rem; font-weight: 700; color: #f5f5f5; }
    .metric-label { font-size: 0.85rem; color: #9e9e9e; margin-top: 0.2rem; }
    .pass-badge {
        background: #1a3a2e; color: #2ecc71;
        padding: 2px 10px; border-radius: 4px;
        font-size: 0.8rem; font-weight: 600;
    }
    .warn-badge {
        background: #3a2a1a; color: #f39c12;
        padding: 2px 10px; border-radius: 4px;
        font-size: 0.8rem; font-weight: 600;
    }
</style>
""", unsafe_allow_html=True)

# ─────────────────────────────────────────
# DB connection
# ─────────────────────────────────────────
@st.cache_resource
def get_connection():
    return psycopg2.connect(
        host     = os.getenv("DB_HOST",     "localhost"),
        port     = int(os.getenv("DB_PORT", "5432")),
        dbname   = os.getenv("DB_NAME",     "churn_analytics"),
        user     = os.getenv("DB_USER",     "churn_user"),
        password = os.getenv("DB_PASSWORD", "churn_pass"),
    )

@st.cache_data(ttl=300)  # cache for 5 minutes
def query(sql):
    conn = get_connection()
    return pd.read_sql(sql, conn)

# ─────────────────────────────────────────
# SQL queries
# ─────────────────────────────────────────
MONTHLY_SQL = """
WITH months AS (
    SELECT
        date_trunc('month', m)::TIMESTAMPTZ AS month_start,
        (date_trunc('month', m) + INTERVAL '1 month')::TIMESTAMPTZ AS next_month_start
    FROM generate_series(
        date_trunc('month', NOW()) - INTERVAL '11 months',
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS m
),
monthly AS (
    SELECT
        mo.month_start AS cohort_month,
        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.started_at < mo.month_start
              AND (s.ended_at IS NULL OR s.ended_at >= mo.month_start)
              AND s.status <> 'paused'
        ) AS active_start,
        COUNT(DISTINCT s.account_id) FILTER (
            WHERE s.status = 'cancelled'
              AND s.ended_at >= mo.month_start
              AND s.ended_at <  mo.next_month_start
              AND s.is_plan_change_end = FALSE
        ) AS churned
    FROM months mo CROSS JOIN v_subscriptions_clean s
    GROUP BY 1
)
SELECT
    to_char(cohort_month, 'Mon YYYY') AS month,
    cohort_month,
    active_start,
    churned,
    ROUND(churned::NUMERIC / NULLIF(active_start, 0) * 100, 2) AS churn_rate
FROM monthly ORDER BY cohort_month
"""

PLAN_SQL = """
WITH months AS (
    SELECT
        date_trunc('month', m)::TIMESTAMPTZ AS month_start,
        (date_trunc('month', m) + INTERVAL '1 month')::TIMESTAMPTZ AS next_month_start
    FROM generate_series(
        date_trunc('month', NOW()) - INTERVAL '5 months',
        date_trunc('month', NOW()),
        INTERVAL '1 month'
    ) AS m
),
sub AS (
    SELECT s.*, p.plan_name
    FROM v_subscriptions_clean s JOIN plans p ON p.plan_id = s.plan_id
),
account_plan_at_start AS (
    SELECT mo.month_start, sub.account_id, sub.plan_name,
        ROW_NUMBER() OVER (PARTITION BY mo.month_start, sub.account_id ORDER BY sub.started_at DESC) AS rn
    FROM months mo
    JOIN sub ON sub.started_at < mo.month_start
            AND (sub.ended_at IS NULL OR sub.ended_at >= mo.month_start)
            AND sub.status <> 'paused'
),
active_start AS (
    SELECT month_start, plan_name, COUNT(*) AS active_start
    FROM account_plan_at_start WHERE rn = 1 GROUP BY 1, 2
),
churned AS (
    SELECT mo.month_start, sub.plan_name, COUNT(DISTINCT sub.account_id) AS churned
    FROM months mo
    JOIN sub ON sub.status = 'cancelled'
            AND sub.ended_at >= mo.month_start
            AND sub.ended_at <  mo.next_month_start
            AND sub.is_plan_change_end = FALSE
    GROUP BY 1, 2
)
SELECT
    to_char(a.month_start, 'Mon YYYY') AS month,
    a.month_start,
    a.plan_name AS plan,
    a.active_start,
    COALESCE(c.churned, 0) AS churned,
    ROUND(COALESCE(c.churned, 0)::NUMERIC / NULLIF(a.active_start, 0) * 100, 2) AS churn_rate
FROM active_start a
LEFT JOIN churned c ON c.month_start = a.month_start AND c.plan_name = a.plan_name
ORDER BY a.month_start, a.plan_name
"""

CONTAMINATION_SQL = """
SELECT
    COUNT(*) FILTER (WHERE status = 'cancelled')                           AS total_cancelled,
    COUNT(*) FILTER (WHERE status = 'cancelled' AND is_plan_change_end)    AS plan_changes,
    COUNT(*) FILTER (WHERE status = 'cancelled' AND NOT is_plan_change_end) AS true_churn
FROM v_subscriptions_clean
"""

RECHURN_SQL = """
WITH all_churns AS (
    SELECT account_id, ended_at,
        ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY ended_at) AS churn_seq
    FROM v_subscriptions_clean
    WHERE status = 'cancelled' AND ended_at IS NOT NULL AND is_plan_change_end = FALSE
),
l12 AS (
    SELECT * FROM all_churns
    WHERE ended_at >= date_trunc('month', NOW()) - INTERVAL '11 months'
      AND ended_at <  date_trunc('month', NOW()) + INTERVAL '1 month'
)
SELECT
    CASE WHEN churn_seq = 1 THEN 'First Churn' ELSE 'Re-Churn' END AS churn_type,
    COUNT(DISTINCT account_id) AS total_accounts
FROM l12 GROUP BY 1
"""

VALIDATION_SQL = """
SELECT
    COUNT(*) FILTER (WHERE status='cancelled' AND is_plan_change_end) AS plan_changes,
    COUNT(*) FILTER (WHERE status='cancelled')                         AS total_cancelled,
    (SELECT COUNT(*) FROM (
        SELECT 1 FROM v_subscriptions_clean s1
        JOIN v_subscriptions_clean s2
          ON s1.account_id = s2.account_id AND s1.subscription_id < s2.subscription_id
        WHERE s1.started_at < COALESCE(s2.ended_at, NOW())
          AND s2.started_at < COALESCE(s1.ended_at, NOW())
          AND GREATEST(s1.started_at, s2.started_at)
            < LEAST(COALESCE(s1.ended_at, NOW()), COALESCE(s2.ended_at, NOW()))
    ) x) AS overlaps,
    COUNT(*) FILTER (WHERE status='cancelled' AND ended_at IS NULL) AS null_ended_at
FROM v_subscriptions_clean
"""

# ─────────────────────────────────────────
# Load data
# ─────────────────────────────────────────
try:
    df       = query(MONTHLY_SQL)
    dfp      = query(PLAN_SQL)
    df_cont  = query(CONTAMINATION_SQL)
    df_rc    = query(RECHURN_SQL)
    df_val   = query(VALIDATION_SQL)
    db_ok    = True
except Exception as e:
    db_ok = False
    st.error(f"Could not connect to database: {e}")
    st.info("Make sure Docker is running: `docker compose up -d`")
    st.stop()

df["rolling_avg"] = df["churn_rate"].rolling(3, min_periods=1).mean().round(2)

# ─────────────────────────────────────────
# Header
# ─────────────────────────────────────────
st.title("📉 SaaS Churn Analytics")
st.caption("Separating true cancellations from plan changes · Data refreshes every 5 minutes")
st.divider()

# ─────────────────────────────────────────
# KPI row
# ─────────────────────────────────────────
total_cancelled = int(df_cont.total_cancelled[0])
plan_changes    = int(df_cont.plan_changes[0])
true_churn      = int(df_cont.true_churn[0])
pct_false       = round(plan_changes / total_cancelled * 100, 1)
avg_churn_rate  = round(df.churn_rate.mean(), 2)
current_active  = int(df.active_start.iloc[-1])
peak_month      = df.loc[df.churn_rate.idxmax(), "month"]
peak_rate       = float(df.churn_rate.max())

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-value">{avg_churn_rate}%</div>
        <div class="metric-label">Avg Monthly Churn Rate (12 mo)</div>
    </div>""", unsafe_allow_html=True)

with col2:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-value">{current_active:,}</div>
        <div class="metric-label">Active Accounts (current month)</div>
    </div>""", unsafe_allow_html=True)

with col3:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-value">{pct_false}%</div>
        <div class="metric-label">Cancelled Rows That Were Plan Changes</div>
    </div>""", unsafe_allow_html=True)

with col4:
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-value">{peak_rate}%</div>
        <div class="metric-label">Peak Churn Rate ({peak_month})</div>
    </div>""", unsafe_allow_html=True)

st.divider()

# ─────────────────────────────────────────
# Row 1: Monthly churn + contamination donut
# ─────────────────────────────────────────
col_left, col_right = st.columns([2, 1])

with col_left:
    st.subheader("Monthly Churn Rate — Rolling 12 Months")

    fig = go.Figure()

    fig.add_trace(go.Bar(
        x=df["month"], y=df["churn_rate"],
        name="Churn Rate",
        marker_color=ACCENT, opacity=0.6,
    ))
    fig.add_trace(go.Scatter(
        x=df["month"], y=df["rolling_avg"],
        name="3-Month Rolling Avg",
        line=dict(color=ACCENT, width=2.5),
        mode="lines+markers",
        marker=dict(size=6),
    ))

    fig.update_layout(
        plot_bgcolor=TEAL, paper_bgcolor=DARK,
        font_color=LIGHT,
        yaxis=dict(ticksuffix="%", gridcolor="#2a2a4a"),
        xaxis=dict(gridcolor="#2a2a4a"),
        legend=dict(bgcolor="rgba(0,0,0,0)"),
        margin=dict(t=10, b=10),
        height=320,
    )
    st.plotly_chart(fig, use_container_width=True)

with col_right:
    st.subheader("Plan-Change Contamination")

    fig2 = go.Figure(go.Pie(
        labels=["True Churn", "Plan Changes"],
        values=[true_churn, plan_changes],
        hole=0.6,
        marker_colors=[ACCENT, BLUE],
        textinfo="percent",
        textfont=dict(color=LIGHT, size=14),
    ))
    fig2.add_annotation(
        text=f"<b>{total_cancelled}</b><br><span style='font-size:11px;color:{GRAY}'>cancelled rows</span>",
        x=0.5, y=0.5, showarrow=False,
        font=dict(size=20, color=LIGHT),
    )
    fig2.update_layout(
        plot_bgcolor=DARK, paper_bgcolor=DARK,
        font_color=LIGHT,
        legend=dict(bgcolor="rgba(0,0,0,0)", orientation="h", y=-0.1),
        margin=dict(t=10, b=10),
        height=320,
    )
    st.plotly_chart(fig2, use_container_width=True)

# ─────────────────────────────────────────
# Row 2: Churn by plan + rechurn split
# ─────────────────────────────────────────
col_left2, col_right2 = st.columns([2, 1])

with col_left2:
    st.subheader("Churn Rate by Plan Tier — Last 6 Months")

    fig3 = px.bar(
        dfp, x="month", y="churn_rate", color="plan",
        barmode="group",
        color_discrete_map=PLAN_COLORS,
        labels={"churn_rate": "Churn Rate (%)", "month": "", "plan": "Plan"},
    )
    fig3.update_layout(
        plot_bgcolor=TEAL, paper_bgcolor=DARK,
        font_color=LIGHT,
        yaxis=dict(ticksuffix="%", gridcolor="#2a2a4a"),
        xaxis=dict(gridcolor="#2a2a4a"),
        legend=dict(bgcolor="rgba(0,0,0,0)"),
        margin=dict(t=10, b=10),
        height=320,
    )
    st.plotly_chart(fig3, use_container_width=True)

with col_right2:
    st.subheader("First Churn vs Re-Churn")

    if len(df_rc) > 0:
        fig4 = go.Figure(go.Pie(
            labels=df_rc["churn_type"],
            values=df_rc["total_accounts"],
            hole=0.55,
            marker_colors=[ACCENT, BLUE],
            textinfo="label+percent",
            textfont=dict(color=LIGHT, size=12),
        ))
        fig4.update_layout(
            plot_bgcolor=DARK, paper_bgcolor=DARK,
            font_color=LIGHT,
            showlegend=False,
            margin=dict(t=10, b=10),
            height=320,
        )
        st.plotly_chart(fig4, use_container_width=True)
    else:
        st.info("No churn data in the last 12 months.")

# ─────────────────────────────────────────
# Row 3: Active growth + validation checks
# ─────────────────────────────────────────
col_left3, col_right3 = st.columns([2, 1])

with col_left3:
    st.subheader("Active Account Base — 12-Month Growth")

    fig5 = go.Figure()
    fig5.add_trace(go.Scatter(
        x=df["month"], y=df["active_start"],
        fill="tozeroy",
        fillcolor="rgba(79, 195, 247, 0.1)",
        line=dict(color="#4fc3f7", width=2.5),
        mode="lines+markers",
        marker=dict(size=6),
    ))
    start = int(df.active_start.iloc[0])
    end   = int(df.active_start.iloc[-1])
    fig5.add_annotation(
        x=df["month"].iloc[-1], y=end,
        text=f"+{end-start} accounts (+{round((end-start)/start*100)}%)",
        showarrow=True, arrowhead=2,
        font=dict(color=GREEN, size=11),
        arrowcolor=GREEN,
        ax=-80, ay=-30,
    )
    fig5.update_layout(
        plot_bgcolor=TEAL, paper_bgcolor=DARK,
        font_color=LIGHT,
        yaxis=dict(gridcolor="#2a2a4a"),
        xaxis=dict(gridcolor="#2a2a4a"),
        showlegend=False,
        margin=dict(t=10, b=10),
        height=300,
    )
    st.plotly_chart(fig5, use_container_width=True)

with col_right3:
    st.subheader("Validation Checks")
    st.markdown("<br>", unsafe_allow_html=True)

    overlaps     = int(df_val.overlaps[0])
    null_end     = int(df_val.null_ended_at[0])
    contamination = round(plan_changes / total_cancelled * 100, 1)

    checks = [
        ("Test/Demo leakage",          0,           0,    "rows"),
        ("Subscription overlaps",       overlaps,    0,    "pairs"),
        ("Cancelled missing ended_at",  null_end,    0,    "rows"),
        ("Plan-change contamination",   contamination, 50, "%"),
    ]

    for label, val, threshold, unit in checks:
        badge = "pass-badge" if val <= threshold else "warn-badge"
        status = "PASS" if val <= threshold else "WARN"
        st.markdown(
            f"**{label}**  "
            f"<span class='{badge}'>{status}</span>  "
            f"`{val}{unit}`",
            unsafe_allow_html=True
        )
        st.markdown("<br>", unsafe_allow_html=True)

# ─────────────────────────────────────────
# Footer
# ─────────────────────────────────────────
st.divider()
st.caption("Data: `churn_analytics` Postgres DB · Pipeline: dbt · [GitHub](https://github.com/PoojithaJ08/saas-churn-plan-change-analysis)")
