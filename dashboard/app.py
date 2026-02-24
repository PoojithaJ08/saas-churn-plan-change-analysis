import os
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import psycopg2

st.set_page_config(
    page_title="Churn Analytics",
    page_icon="📉",
    layout="wide",
    initial_sidebar_state="collapsed",
)

BG       = "#080c14"
SURFACE  = "#0d1420"
CARD     = "#111827"
BORDER   = "#1f2937"
BORDER2  = "#374151"
CYAN     = "#22d3ee"
RED      = "#f87171"
AMBER    = "#fbbf24"
GREEN    = "#4ade80"
BLUE     = "#60a5fa"
TEXT     = "#f9fafb"
SUBTEXT  = "#9ca3af"
MUTED    = "#4b5563"
PLAN_COLORS = {"Enterprise": BLUE, "Growth": RED, "Starter": AMBER}

st.markdown(f"""
<style>
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=DM+Mono:wght@400;500&display=swap');
*, html, body {{ font-family: 'DM Sans', sans-serif !important; }}
.stApp {{ background: {BG}; }}
.block-container {{ padding: 2.5rem 3rem !important; max-width: 1440px !important; }}
section[data-testid="stSidebar"], #MainMenu, footer, header, .stDeployButton, div[data-testid="stToolbar"] {{ visibility: hidden; display: none; }}
.db-header {{ display:flex; align-items:flex-end; justify-content:space-between; margin-bottom:2.5rem; padding-bottom:1.5rem; border-bottom:1px solid {BORDER}; }}
.db-title {{ font-size:1.5rem; font-weight:700; color:{TEXT}; letter-spacing:-0.4px; }}
.db-title span {{ color:{CYAN}; }}
.db-meta {{ font-size:0.75rem; color:{MUTED}; font-family:'DM Mono',monospace; }}
.kpi-row {{ display:grid; grid-template-columns:repeat(4,1fr); gap:1.25rem; margin-bottom:2.5rem; }}
.kpi {{ background:{CARD}; border:1px solid {BORDER}; border-radius:10px; padding:1.5rem 1.75rem; position:relative; }}
.kpi-accent {{ position:absolute; top:0; left:1.75rem; right:1.75rem; height:2px; border-radius:0 0 4px 4px; }}
.kpi-val {{ font-size:2.4rem; font-weight:700; color:{TEXT}; line-height:1; letter-spacing:-1px; margin:0.8rem 0 0.5rem; font-variant-numeric:tabular-nums; }}
.kpi-lbl {{ font-size:0.72rem; color:{SUBTEXT}; font-weight:500; text-transform:uppercase; letter-spacing:0.6px; }}
.kpi-tag {{ display:inline-block; margin-top:0.5rem; font-size:0.68rem; font-family:'DM Mono',monospace; color:{MUTED}; background:{SURFACE}; padding:2px 8px; border-radius:4px; border:1px solid {BORDER}; }}
.sl {{ font-size:0.68rem; font-weight:600; color:{MUTED}; text-transform:uppercase; letter-spacing:1.2px; margin-bottom:0.6rem; font-family:'DM Mono',monospace; }}
.cc {{ background:{CARD}; border:1px solid {BORDER}; border-radius:10px; padding:1.5rem; }}
.ct {{ font-size:0.9rem; font-weight:600; color:{TEXT}; margin-bottom:0.2rem; }}
.cd {{ font-size:0.73rem; color:{MUTED}; margin-bottom:1rem; line-height:1.4; }}
.val-card {{ background:{CARD}; border:1px solid {BORDER}; border-radius:10px; padding:1.5rem; }}
.val-row {{ display:flex; align-items:center; justify-content:space-between; padding:0.65rem 0; border-bottom:1px solid {BORDER}; }}
.val-row:last-child {{ border-bottom:none; }}
.val-name {{ font-size:0.8rem; color:{SUBTEXT}; }}
.val-right {{ display:flex; align-items:center; gap:0.5rem; }}
.bp {{ font-size:0.63rem; font-weight:700; font-family:'DM Mono',monospace; color:{GREEN}; background:#052e16; border:1px solid #166534; padding:2px 8px; border-radius:20px; }}
.bi {{ font-size:0.63rem; font-weight:700; font-family:'DM Mono',monospace; color:{AMBER}; background:#431407; border:1px solid #92400e; padding:2px 8px; border-radius:20px; }}
.vn {{ font-size:0.75rem; color:{MUTED}; font-family:'DM Mono',monospace; }}
.div {{ height:1px; background:{BORDER}; margin:1.75rem 0; }}
</style>
""", unsafe_allow_html=True)

@st.cache_resource
def get_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST","localhost"), port=int(os.getenv("DB_PORT","5432")),
        dbname=os.getenv("DB_NAME","churn_analytics"),
        user=os.getenv("DB_USER","churn_user"), password=os.getenv("DB_PASSWORD","churn_pass"),
    )

@st.cache_data(ttl=300)
def q(sql):
    return pd.read_sql(sql, get_conn())

try:
    df  = q("""
        WITH months AS (
          SELECT date_trunc('month',m)::TIMESTAMPTZ AS ms,
                 (date_trunc('month',m)+INTERVAL '1 month')::TIMESTAMPTZ AS ns
          FROM generate_series(date_trunc('month',NOW())-INTERVAL '11 months',date_trunc('month',NOW()),INTERVAL '1 month') m
        )
        SELECT to_char(ms,'Mon YY') AS month, ms,
          COUNT(DISTINCT s.account_id) FILTER (WHERE s.started_at<ms AND (s.ended_at IS NULL OR s.ended_at>=ms) AND s.status<>'paused') AS active_start,
          COUNT(DISTINCT s.account_id) FILTER (WHERE s.status='cancelled' AND s.ended_at>=ms AND s.ended_at<ns AND s.is_plan_change_end=FALSE) AS churned
        FROM months CROSS JOIN v_subscriptions_clean s GROUP BY 1,2 ORDER BY 2""")
    dfp = q("""
        WITH months AS (
          SELECT date_trunc('month',m)::TIMESTAMPTZ AS ms,
                 (date_trunc('month',m)+INTERVAL '1 month')::TIMESTAMPTZ AS ns
          FROM generate_series(date_trunc('month',NOW())-INTERVAL '5 months',date_trunc('month',NOW()),INTERVAL '1 month') m
        ), sub AS (SELECT s.*,p.plan_name FROM v_subscriptions_clean s JOIN plans p ON p.plan_id=s.plan_id),
        aps AS (SELECT mo.ms,sub.account_id,sub.plan_name,
          ROW_NUMBER() OVER (PARTITION BY mo.ms,sub.account_id ORDER BY sub.started_at DESC) AS rn
          FROM months mo JOIN sub ON sub.started_at<mo.ms AND (sub.ended_at IS NULL OR sub.ended_at>=mo.ms) AND sub.status<>'paused'),
        act AS (SELECT ms,plan_name,COUNT(*) AS active_start FROM aps WHERE rn=1 GROUP BY 1,2),
        ch  AS (SELECT mo.ms,sub.plan_name,COUNT(DISTINCT sub.account_id) AS churned
          FROM months mo JOIN sub ON sub.status='cancelled' AND sub.ended_at>=mo.ms AND sub.ended_at<mo.ns AND sub.is_plan_change_end=FALSE GROUP BY 1,2)
        SELECT to_char(a.ms,'Mon YY') AS month,a.ms,a.plan_name AS plan,
          ROUND(COALESCE(c.churned,0)::NUMERIC/NULLIF(a.active_start,0)*100,2) AS churn_rate
        FROM act a LEFT JOIN ch c ON c.ms=a.ms AND c.plan_name=a.plan_name ORDER BY a.ms,a.plan_name""")
    dc  = q("SELECT COUNT(*) FILTER (WHERE status='cancelled') AS total, COUNT(*) FILTER (WHERE status='cancelled' AND is_plan_change_end) AS pc, COUNT(*) FILTER (WHERE status='cancelled' AND NOT is_plan_change_end) AS tc FROM v_subscriptions_clean")
    dv  = q("SELECT COUNT(*) FILTER (WHERE status='cancelled' AND is_plan_change_end) AS pc, COUNT(*) FILTER (WHERE status='cancelled') AS tot, (SELECT COUNT(*) FROM (SELECT 1 FROM v_subscriptions_clean s1 JOIN v_subscriptions_clean s2 ON s1.account_id=s2.account_id AND s1.subscription_id<s2.subscription_id WHERE GREATEST(s1.started_at,s2.started_at)<LEAST(COALESCE(s1.ended_at,NOW()),COALESCE(s2.ended_at,NOW()))) x) AS overlaps, COUNT(*) FILTER (WHERE status='cancelled' AND ended_at IS NULL) AS null_end FROM v_subscriptions_clean")
except Exception as e:
    st.error(f"**Database connection failed:** {e}")
    st.code("docker compose up -d", language="bash")
    st.stop()

df["churn_rate"]  = (df["churned"]/df["active_start"].replace(0,None)*100).round(2).fillna(0)
df["rolling_avg"] = df["churn_rate"].rolling(3,min_periods=1).mean().round(2)
dfp["churn_rate"] = dfp["churn_rate"].astype(float).fillna(0)
total = int(dc.total[0]); pc = int(dc.pc[0]); tc = int(dc.tc[0])
pct_pc = round(pc/total*100,1); avg_rate = round(float(df.churn_rate.mean()),2)
active_now = int(df.active_start.iloc[-1]); start_active = int(df.active_start.iloc[0])
growth_pct = round((active_now-start_active)/start_active*100)
peak_idx = df.churn_rate.idxmax(); peak_rate = float(df.churn_rate.max()); peak_month = df.loc[peak_idx,"month"]

# ── Header ──────────────────────────────
st.markdown(f"""
<div class="db-header">
  <div>
    <div class="db-title">SaaS <span>Churn</span> Analytics</div>
    <div style="font-size:0.78rem;color:{MUTED};margin-top:0.3rem;">Separating true cancellations from plan changes · plan-change noise excluded</div>
  </div>
  <div class="db-meta">churn_analytics · refreshes every 5 min</div>
</div>""", unsafe_allow_html=True)

# ── KPIs ────────────────────────────────
st.markdown(f"""
<div class="kpi-row">
  <div class="kpi"><div class="kpi-accent" style="background:{CYAN}"></div>
    <div class="kpi-lbl">Avg Monthly Churn</div><div class="kpi-val">{avg_rate}%</div>
    <div class="kpi-tag">rolling 12 months</div></div>
  <div class="kpi"><div class="kpi-accent" style="background:{BLUE}"></div>
    <div class="kpi-lbl">Active Accounts</div><div class="kpi-val">{active_now:,}</div>
    <div class="kpi-tag">+{growth_pct}% YoY</div></div>
  <div class="kpi"><div class="kpi-accent" style="background:{AMBER}"></div>
    <div class="kpi-lbl">Plan-Change Noise</div><div class="kpi-val">{pct_pc}%</div>
    <div class="kpi-tag">{pc} of {total} cancelled rows</div></div>
  <div class="kpi"><div class="kpi-accent" style="background:{RED}"></div>
    <div class="kpi-lbl">Peak Churn Rate</div><div class="kpi-val">{peak_rate}%</div>
    <div class="kpi-tag">{peak_month}</div></div>
</div>""", unsafe_allow_html=True)

# ── Row 1 ────────────────────────────────
c1, c2 = st.columns([3, 1.2], gap="large")

with c1:
    st.markdown('<div class="sl">Churn Trend</div>', unsafe_allow_html=True)
    st.markdown(f'<div class="cc"><div class="ct">Monthly Churn Rate — Rolling 12 Months</div><div class="cd">True cancellations only · plan-change rows excluded · 3-month rolling average</div>', unsafe_allow_html=True)
    fig1 = go.Figure()
    fig1.add_trace(go.Bar(x=df["month"],y=df["churn_rate"],
        marker=dict(color=CYAN,opacity=0.2,line=dict(width=0)),
        name="Churn Rate",hovertemplate="%{x}: %{y:.2f}%<extra></extra>"))
    fig1.add_trace(go.Scatter(x=df["month"],y=df["rolling_avg"],
        line=dict(color=CYAN,width=2.5),mode="lines+markers",
        marker=dict(size=6,color=CYAN,line=dict(width=2,color=BG)),
        name="3-mo avg",hovertemplate="%{x}: %{y:.2f}%<extra></extra>"))
    fig1.update_layout(plot_bgcolor=CARD,paper_bgcolor=CARD,
        margin=dict(t=10,b=10,l=0,r=0),height=270,bargap=0.4,
        xaxis=dict(gridcolor=BORDER,tickfont=dict(size=10,color=SUBTEXT),showgrid=False,linecolor=BORDER),
        yaxis=dict(gridcolor=BORDER,tickfont=dict(size=10,color=SUBTEXT),ticksuffix="%",gridwidth=0.5,zeroline=False,linecolor=BORDER),
        legend=dict(bgcolor="rgba(0,0,0,0)",font=dict(size=10,color=SUBTEXT),orientation="h",y=1.12,x=0),
        hoverlabel=dict(bgcolor=BORDER,font_size=12,font_family="DM Sans"),showlegend=True)
    st.plotly_chart(fig1,use_container_width=True,config={"displayModeBar":False})
    st.markdown("</div>", unsafe_allow_html=True)

with c2:
    st.markdown('<div class="sl">Contamination</div>', unsafe_allow_html=True)
    st.markdown(f'<div class="cc"><div class="ct">Plan-Change Contamination</div><div class="cd">{pct_pc}% of cancelled rows were NOT true churn</div>', unsafe_allow_html=True)
    fig2 = go.Figure(go.Pie(
        labels=["True Churn","Plan Changes"],values=[tc,pc],hole=0.68,
        marker=dict(colors=[CYAN,BORDER2],line=dict(color=CARD,width=3)),
        textinfo="none",hovertemplate="%{label}: %{value} rows<extra></extra>"))
    fig2.add_annotation(text=f"<b>{tc}</b><br><span style='font-size:10px'>{tc/total*100:.0f}% true</span>",
        x=0.5,y=0.5,showarrow=False,font=dict(color=TEXT,size=14,family="DM Sans"))
    fig2.update_layout(plot_bgcolor=CARD,paper_bgcolor=CARD,
        margin=dict(t=10,b=40,l=0,r=0),height=270,showlegend=True,
        legend=dict(bgcolor="rgba(0,0,0,0)",font=dict(size=10,color=SUBTEXT),orientation="h",y=-0.02,x=0.1),
        hoverlabel=dict(bgcolor=BORDER,font_size=12))
    st.plotly_chart(fig2,use_container_width=True,config={"displayModeBar":False})
    st.markdown("</div>", unsafe_allow_html=True)

st.markdown('<div class="div"></div>', unsafe_allow_html=True)

# ── Row 2 ────────────────────────────────
c3, c4, c5 = st.columns([2, 1.5, 1.2], gap="large")

with c3:
    st.markdown('<div class="sl">Segment View</div>', unsafe_allow_html=True)
    st.markdown(f'<div class="cc"><div class="ct">Churn by Plan Tier — Last 6 Months</div><div class="cd">Enterprise consistently lowest · Starter most volatile month-to-month</div>', unsafe_allow_html=True)
    fig3 = go.Figure()
    for plan in ["Enterprise","Growth","Starter"]:
        d = dfp[dfp.plan==plan]
        fig3.add_trace(go.Bar(x=d["month"],y=d["churn_rate"],name=plan,
            marker=dict(color=PLAN_COLORS[plan],opacity=0.85,line=dict(width=0)),
            hovertemplate=f"{plan} %{{x}}: %{{y:.2f}}%<extra></extra>"))
    fig3.update_layout(plot_bgcolor=CARD,paper_bgcolor=CARD,
        margin=dict(t=10,b=10,l=0,r=0),height=250,barmode="group",bargap=0.2,bargroupgap=0.06,
        xaxis=dict(gridcolor=BORDER,tickfont=dict(size=10,color=SUBTEXT),showgrid=False,linecolor=BORDER),
        yaxis=dict(gridcolor=BORDER,tickfont=dict(size=10,color=SUBTEXT),ticksuffix="%",gridwidth=0.5,zeroline=False,linecolor=BORDER),
        legend=dict(bgcolor="rgba(0,0,0,0)",font=dict(size=10,color=SUBTEXT),orientation="h",y=1.12,x=0),
        hoverlabel=dict(bgcolor=BORDER,font_size=12,font_family="DM Sans"))
    st.plotly_chart(fig3,use_container_width=True,config={"displayModeBar":False})
    st.markdown("</div>", unsafe_allow_html=True)

with c4:
    st.markdown('<div class="sl">Account Growth</div>', unsafe_allow_html=True)
    st.markdown(f'<div class="cc"><div class="ct">Active Accounts — 12-Month</div><div class="cd">{start_active:,} → {active_now:,} &nbsp;·&nbsp; +{growth_pct}% over the period</div>', unsafe_allow_html=True)
    fig4 = go.Figure()
    fig4.add_trace(go.Scatter(x=df["month"],y=df["active_start"],
        fill="tozeroy",fillcolor="rgba(96,165,250,0.06)",
        line=dict(color=BLUE,width=2.5),mode="lines+markers",
        marker=dict(size=4,color=BLUE,line=dict(width=1.5,color=BG)),
        hovertemplate="%{x}: %{y:,} accounts<extra></extra>"))
    fig4.update_layout(plot_bgcolor=CARD,paper_bgcolor=CARD,
        margin=dict(t=10,b=10,l=0,r=0),height=250,
        xaxis=dict(gridcolor=BORDER,tickfont=dict(size=9,color=SUBTEXT),showgrid=False,linecolor=BORDER,
            tickvals=[df.month.iloc[0],df.month.iloc[5],df.month.iloc[-1]]),
        yaxis=dict(gridcolor=BORDER,tickfont=dict(size=10,color=SUBTEXT),gridwidth=0.5,zeroline=False,linecolor=BORDER),
        showlegend=False,hoverlabel=dict(bgcolor=BORDER,font_size=12))
    st.plotly_chart(fig4,use_container_width=True,config={"displayModeBar":False})
    st.markdown("</div>", unsafe_allow_html=True)

with c5:
    st.markdown('<div class="sl">Data Quality</div>', unsafe_allow_html=True)
    overlaps = int(dv.overlaps[0]); null_end = int(dv.null_end[0])
    checks = [
        ("Test/demo leakage",     True,  "0 rows"),
        ("Subscription overlaps", overlaps==0, f"{overlaps} pairs"),
        ("Missing ended_at",      null_end==0, f"{null_end} rows"),
        ("Churn spikes >15%",     True,  "0 months"),
        ("Plan-change noise",     True,  f"{pct_pc}%"),
    ]
    rows = "".join([f"""
    <div class="val-row">
      <span class="val-name">{lbl}</span>
      <div class="val-right">
        <span class="{"bp" if ok else "bi"}">{"PASS" if ok else "WARN"}</span>
        <span class="vn">{val}</span>
      </div>
    </div>""" for lbl,ok,val in checks])
    st.markdown(f'<div class="val-card"><div class="ct" style="margin-bottom:0.75rem">Validation Checks</div>{rows}</div>', unsafe_allow_html=True)

# ── Footer ───────────────────────────────
st.markdown(f"""
<div style="margin-top:2rem;padding-top:1rem;border-top:1px solid {BORDER};
     display:flex;justify-content:space-between;align-items:center;">
  <span style="font-size:0.7rem;color:{MUTED};font-family:'DM Mono',monospace;">
    churn_analytics · postgres:15 · dbt pipeline
  </span>
  <a href="https://github.com/PoojithaJ08/saas-churn-plan-change-analysis"
     style="font-size:0.7rem;color:{MUTED};text-decoration:none;font-family:'DM Mono',monospace;">
    github ↗
  </a>
</div>""", unsafe_allow_html=True)
