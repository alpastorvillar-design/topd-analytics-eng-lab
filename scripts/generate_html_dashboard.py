"""
generate_html_dashboard.py

Queries dbt_marts in BigQuery and writes dashboards/mediconnect_dashboard.html
from scratch.  The full visual design is embedded in HTML_TEMPLATE below;
the script replaces the %%DATA%% placeholder with fresh numbers from BigQuery.

Run from project root:
    python scripts/generate_html_dashboard.py
"""

import json
from pathlib import Path
from google.cloud import bigquery
from dotenv import load_dotenv

load_dotenv()
c = bigquery.Client(project='topd-lab', location='EU')

print("Querying BigQuery...")

# ── Page 1: KPIs + monthly charts ─────────────────────────────────────────
kpis = list(c.query("""
SELECT
  MAX(cumulative_revenue_eur)     AS revenue_acumulado,
  SUM(completed_appointments)     AS citas_completadas,
  AVG(completion_rate) * 100      AS tasa_completado,
  AVG(lead_conversion_rate) * 100 AS conversion_leads
FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
""").result())[0]

monthly = list(c.query("""
SELECT
  FORMAT_DATE('%Y-%m', date)      AS mes,
  SUM(daily_revenue_eur)          AS revenue,
  SUM(completed_appointments)     AS citas
FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
GROUP BY 1 ORDER BY 1
""").result())

# ── Page 2: Cohort retention ───────────────────────────────────────────────
cohort = list(c.query("""
SELECT
  FORMAT_DATE('%Y-%m', cohort_month) AS cohort,
  months_since_acquisition           AS mes_num,
  ROUND(AVG(retention_rate)*100, 1)  AS retencion
FROM `topd-lab.dbt_marts.mart_patient_retention`
GROUP BY 1, 2 ORDER BY 1, 2
""").result())

retention_m1 = list(c.query("""
SELECT ROUND(AVG(retention_rate)*100,1) AS v
FROM `topd-lab.dbt_marts.mart_patient_retention`
WHERE months_since_acquisition = 1
""").result())[0]["v"]

retention_m3 = list(c.query("""
SELECT ROUND(AVG(retention_rate)*100,1) AS v
FROM `topd-lab.dbt_marts.mart_patient_retention`
WHERE months_since_acquisition = 3
""").result())[0]["v"]

# ── Page 3: Specialty ──────────────────────────────────────────────────────
specialty = list(c.query("""
SELECT
  specialty_name,
  ROUND(AVG(completion_rate)*100, 1)                           AS tasa,
  ROUND(SUM(total_revenue_eur), 0)                             AS revenue,
  MAX(active_doctors)                                          AS doctores,
  SUM(total_appointments)                                      AS appts,
  ROUND(SAFE_DIVIDE(SUM(total_revenue_eur),
        NULLIF(SUM(completed_appointments),0)), 0)             AS ticket_medio
FROM `topd-lab.dbt_marts.agg_specialty_performance`
GROUP BY 1 ORDER BY revenue DESC
""").result())

data = {
    "kpis": {
        "revenue":    round(kpis["revenue_acumulado"], 0),
        "citas":      int(kpis["citas_completadas"]),
        "tasa":       round(kpis["tasa_completado"], 1),
        "conversion": round(kpis["conversion_leads"], 1),
    },
    "monthly": [{"mes": r["mes"], "revenue": round(r["revenue"],0), "citas": int(r["citas"])} for r in monthly],
    "cohort":  [{"cohort": r["cohort"], "mes": int(r["mes_num"]), "ret": float(r["retencion"] or 0)} for r in cohort],
    "retention_m1": float(retention_m1 or 0),
    "retention_m3": float(retention_m3 or 0),
    "specialty": [
        {"nombre": r["specialty_name"], "tasa": float(r["tasa"]),
         "revenue": float(r["revenue"]), "doctores": int(r["doctores"]),
         "appts": int(r["appts"]), "ticket": float(r["ticket_medio"] or 0)}
        for r in specialty
    ]
}

print(f"  KPIs:     {data['kpis']}")
print(f"  Monthly:  {len(data['monthly'])} rows")
print(f"  Cohort:   {len(data['cohort'])} rows")
print(f"  Specialty:{len(data['specialty'])} rows")
print(f"  Ret M1={data['retention_m1']}%  M3={data['retention_m3']}%")

# ── HTML template (fully embedded) ────────────────────────────────────────
# The complete visual design lives here.
# %%DATA%% is replaced at write-time with the fresh JSON blob from BigQuery.
HTML_TEMPLATE = """\
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MediConnect Analytics — Cuadro de Mando</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.5.1" integrity="sha384-jb8JQMbMoBUzgWatfe6COACi2ljcDdZQ2OxczGA3bGNeWe+6DChMTBJemed7ZnvJ" crossorigin="anonymous"></script>
<style>
/* ─── Reset & Base ──────────────────────────────────────────────────── */
*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  /* Color system: cool slate + clinical teal + warm amber accents */
  --bg:          #f0f4f8;
  --surface:     #ffffff;
  --surface-2:   #f7f9fc;
  --border:      #dde3ec;
  --border-light:#edf1f7;

  --ink-900:     #0d1b2a;
  --ink-700:     #243b53;
  --ink-500:     #4a6080;
  --ink-400:     #6b7fa0;
  --ink-300:     #96a7bf;
  --ink-200:     #bfcbd9;
  --ink-100:     #e4eaf2;

  --teal-600:    #0d7377;
  --teal-500:    #14939a;
  --teal-400:    #1db5bd;
  --teal-200:    #a4dfe2;
  --teal-100:    #e0f5f6;

  --amber-500:   #c07b00;
  --amber-400:   #e09100;
  --amber-100:   #fdf3dc;

  --green-500:   #1a7f5a;
  --green-400:   #22a06b;
  --green-100:   #dcf5eb;

  --red-500:     #c0392b;
  --red-100:     #fde8e6;

  --header-bg:   #0d1b2a;

  --shadow-sm:   0 1px 3px rgba(13,27,42,.07), 0 1px 2px rgba(13,27,42,.05);
  --shadow-md:   0 4px 12px rgba(13,27,42,.08), 0 2px 4px rgba(13,27,42,.05);
  --shadow-lg:   0 8px 24px rgba(13,27,42,.10), 0 3px 8px rgba(13,27,42,.06);

  --radius-sm:   6px;
  --radius-md:   10px;
  --radius-lg:   14px;

  --font:        -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter', 'Helvetica Neue', sans-serif;
  --font-mono:   'SFMono-Regular', 'Consolas', 'Liberation Mono', monospace;
}

body {
  font-family: var(--font);
  background: var(--bg);
  color: var(--ink-700);
  font-size: 14px;
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}

/* ─── Header ────────────────────────────────────────────────────────── */
.header {
  background: var(--header-bg);
  padding: 0 36px;
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  z-index: 100;
  border-bottom: 1px solid rgba(255,255,255,.06);
}

.header-brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.header-logo {
  width: 28px;
  height: 28px;
  background: var(--teal-500);
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.header-logo svg {
  width: 16px;
  height: 16px;
  fill: #fff;
}

.header h1 {
  font-size: 15px;
  font-weight: 600;
  color: #fff;
  letter-spacing: .2px;
}

.header-meta {
  display: flex;
  align-items: center;
  gap: 20px;
}

.header-badge {
  font-size: 11px;
  font-weight: 500;
  color: var(--teal-200);
  background: rgba(20,147,154,.15);
  border: 1px solid rgba(20,147,154,.25);
  padding: 3px 10px;
  border-radius: 20px;
  letter-spacing: .3px;
}

.header-date {
  font-size: 12px;
  color: var(--ink-300);
}

/* ─── Tab Navigation ────────────────────────────────────────────────── */
.nav {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 0 36px;
  display: flex;
  gap: 0;
}

.tab {
  padding: 0 4px;
  margin-right: 8px;
  height: 48px;
  display: flex;
  align-items: center;
  font-size: 13px;
  font-weight: 500;
  color: var(--ink-400);
  cursor: pointer;
  border-bottom: 2px solid transparent;
  transition: color .18s ease, border-color .18s ease;
  user-select: none;
  white-space: nowrap;
}

.tab:hover:not(.active) {
  color: var(--ink-700);
}

.tab.active {
  color: var(--teal-500);
  border-bottom-color: var(--teal-500);
}

/* ─── Page Layout ───────────────────────────────────────────────────── */
.page {
  display: none;
  padding: 28px 36px 48px;
  max-width: 1440px;
  margin: 0 auto;
  animation: fadeIn .22s ease;
}

.page.active { display: block; }

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(6px); }
  to   { opacity: 1; transform: translateY(0); }
}

.page-title {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .8px;
  color: var(--ink-300);
  margin-bottom: 20px;
}

/* ─── KPI Cards ─────────────────────────────────────────────────────── */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
  margin-bottom: 20px;
}

.kpi-grid-3 {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  margin-bottom: 20px;
  max-width: 700px;
}

.kpi-card {
  background: var(--surface);
  border: 1px solid var(--border-light);
  border-radius: var(--radius-lg);
  padding: 22px 24px;
  box-shadow: var(--shadow-sm);
  transition: box-shadow .18s ease;
  position: relative;
  overflow: hidden;
}

.kpi-card::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 3px;
  background: linear-gradient(90deg, var(--teal-500), var(--teal-400));
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
}

.kpi-card:nth-child(2)::before { background: linear-gradient(90deg, #3b82f6, #60a5fa); }
.kpi-card:nth-child(3)::before { background: linear-gradient(90deg, var(--green-500), var(--green-400)); }
.kpi-card:nth-child(4)::before { background: linear-gradient(90deg, var(--amber-500), var(--amber-400)); }

.kpi-card:hover { box-shadow: var(--shadow-md); }

.kpi-label {
  font-size: 10.5px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .7px;
  color: var(--ink-400);
  margin-bottom: 10px;
}

.kpi-value {
  font-size: 34px;
  font-weight: 700;
  color: var(--ink-900);
  line-height: 1;
  letter-spacing: -.5px;
  font-variant-numeric: tabular-nums;
}

.kpi-value.md { font-size: 28px; letter-spacing: -.4px; }

.kpi-footnote {
  font-size: 11px;
  color: var(--ink-300);
  margin-top: 6px;
}

/* ─── Chart Cards ───────────────────────────────────────────────────── */
.chart-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 20px;
}

.card {
  background: var(--surface);
  border: 1px solid var(--border-light);
  border-radius: var(--radius-lg);
  padding: 22px 24px;
  box-shadow: var(--shadow-sm);
}

.card-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 18px;
}

.card-title {
  font-size: 12.5px;
  font-weight: 600;
  color: var(--ink-700);
  letter-spacing: .1px;
}

.card-subtitle {
  font-size: 11px;
  color: var(--ink-300);
}

.chart-wrap {
  position: relative;
  height: 260px;
}

.chart-wrap canvas {
  position: absolute;
  inset: 0;
  width: 100% !important;
  height: 100% !important;
}

/* ─── Table ─────────────────────────────────────────────────────────── */
.table-card {
  background: var(--surface);
  border: 1px solid var(--border-light);
  border-radius: var(--radius-lg);
  padding: 22px 24px;
  box-shadow: var(--shadow-sm);
  margin-bottom: 20px;
}

.data-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.data-table thead th {
  text-align: left;
  padding: 8px 14px;
  border-bottom: 2px solid var(--border);
  font-size: 10.5px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .6px;
  color: var(--ink-400);
  white-space: nowrap;
}

.data-table tbody td {
  padding: 11px 14px;
  border-bottom: 1px solid var(--border-light);
  color: var(--ink-700);
  vertical-align: middle;
}

.data-table tbody tr:last-child td { border-bottom: none; }

.data-table tbody tr:hover td {
  background: var(--surface-2);
}

.rank-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  background: var(--ink-100);
  color: var(--ink-400);
  font-size: 11px;
  font-weight: 600;
  border-radius: 50%;
  font-variant-numeric: tabular-nums;
}

.rank-badge.top { background: var(--teal-100); color: var(--teal-600); }

.pct-bar-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
}
.pct-bar-track {
  flex: 1;
  height: 5px;
  background: var(--ink-100);
  border-radius: 3px;
  overflow: hidden;
  min-width: 60px;
}
.pct-bar-fill {
  height: 100%;
  border-radius: 3px;
  background: linear-gradient(90deg, var(--teal-500), var(--teal-400));
}

/* ─── Heatmap ───────────────────────────────────────────────────────── */
.heatmap-outer {
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  border-radius: var(--radius-md);
}

.heatmap {
  border-collapse: collapse;
  font-size: 11.5px;
  white-space: nowrap;
  width: 100%;
  table-layout: fixed;
}

.heatmap thead th {
  padding: 6px 7px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--ink-400);
  font-weight: 600;
  font-size: 10px;
  text-align: center;
  letter-spacing: .3px;
  position: sticky;
  top: 0;
}

.heatmap thead th:first-child {
  text-align: center;
  width: 78px;
  position: sticky;
  left: 0;
  z-index: 2;
  background: var(--surface-2);
}

.heatmap tbody td {
  padding: 4px 2px;
  border: 1px solid var(--border-light);
  text-align: center;
  font-size: 10.5px;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
  transition: opacity .1s;
  overflow: hidden;
}

.heatmap tbody td:first-child {
  font-weight: 600;
  font-size: 10px;
  color: var(--ink-500);
  background: var(--surface-2);
  text-align: center;
  border-right: 2px solid var(--border);
  position: sticky;
  left: 0;
}

.heatmap tbody tr:hover td { opacity: .85; }
.heatmap tbody tr:hover td:first-child { opacity: 1; }

/* ─── Heatmap legend ────────────────────────────────────────────────── */
.heatmap-legend {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 14px;
  font-size: 11px;
  color: var(--ink-400);
}

.legend-gradient {
  width: 120px;
  height: 8px;
  border-radius: 4px;
  background: linear-gradient(90deg,
    rgb(232,245,233) 0%,
    rgb(129,199,132) 40%,
    rgb(56,142,60)   75%,
    rgb(27,94,32)    100%
  );
}

/* ─── Footer ─────────────────────────────────────────────────────────── */
.page-footer {
  margin-top: 12px;
  font-size: 11px;
  color: var(--ink-300);
  display: flex;
  align-items: center;
  gap: 6px;
}

.page-footer::before {
  content: '';
  display: inline-block;
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: var(--ink-200);
}

/* ─── Inline stat highlight ──────────────────────────────────────────── */
.stat-tag {
  display: inline-block;
  font-size: 11px;
  font-weight: 600;
  padding: 2px 7px;
  border-radius: 4px;
  font-variant-numeric: tabular-nums;
}

.stat-tag.teal { background: var(--teal-100); color: var(--teal-600); }
.stat-tag.green { background: var(--green-100); color: var(--green-500); }
.stat-tag.amber { background: var(--amber-100); color: var(--amber-500); }

/* ─── Tooltip override ───────────────────────────────────────────────── */
</style>
</head>
<body>

<!-- Header -->
<header class="header">
  <div class="header-brand">
    <div class="header-logo">
      <svg viewBox="0 0 16 16"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zM7 4h2v3h3v2H9v3H7v-3H4V7h3V4z"/></svg>
    </div>
    <h1>MediConnect Analytics</h1>
  </div>
  <div class="header-meta">
    <span class="header-badge">Synthetic eHealth Marketplace</span>
    <span class="header-date">2022 – 2024</span>
  </div>
</header>

<!-- Tab navigation -->
<nav class="nav">
  <div class="tab active" onclick="showPage('p1',this)">Executive Overview</div>
  <div class="tab" onclick="showPage('p2',this)">Patient Retention</div>
  <div class="tab" onclick="showPage('p3',this)">Specialty Performance</div>
</nav>

<!-- ══════════════════════════════════════════════════════════════════════
     PAGE 1 — EXECUTIVE OVERVIEW
     ══════════════════════════════════════════════════════════════════════ -->
<main id="p1" class="page active">
  <p class="page-title">Executive Overview</p>

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-label">Revenue Acumulado</div>
      <div class="kpi-value" id="k-revenue"></div>
      <div class="kpi-footnote">EUR · ene 2022 – dic 2024</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Citas Completadas</div>
      <div class="kpi-value" id="k-citas"></div>
      <div class="kpi-footnote">de ~60.000 citas totales</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Tasa de Completado</div>
      <div class="kpi-value" id="k-tasa"></div>
      <div class="kpi-footnote">citas completadas / programadas</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Conversión de Leads</div>
      <div class="kpi-value" id="k-conv"></div>
      <div class="kpi-footnote">sobre ~100.000 leads</div>
    </div>
  </div>

  <div class="chart-grid">
    <div class="card">
      <div class="card-header">
        <span class="card-title">Revenue Mensual</span>
        <span class="card-subtitle">EUR · 36 meses</span>
      </div>
      <div class="chart-wrap"><canvas id="c-revenue"></canvas></div>
    </div>
    <div class="card">
      <div class="card-header">
        <span class="card-title">Citas Completadas por Mes</span>
        <span class="card-subtitle">unidades</span>
      </div>
      <div class="chart-wrap"><canvas id="c-citas"></canvas></div>
    </div>
  </div>

  <div class="page-footer">Datos: 2022–2024 · 15.000 pacientes · 60.000 citas · 100.000 leads · Fuente: dbt_marts, BigQuery EU</div>
</main>

<!-- ══════════════════════════════════════════════════════════════════════
     PAGE 2 — PATIENT RETENTION
     ══════════════════════════════════════════════════════════════════════ -->
<main id="p2" class="page">
  <p class="page-title">Patient Retention</p>

  <div class="kpi-grid-3">
    <div class="kpi-card">
      <div class="kpi-label">Cohortes Analizadas</div>
      <div class="kpi-value md">36</div>
      <div class="kpi-footnote">ene 2022 – dic 2024</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Retención Mes 1</div>
      <div class="kpi-value md" id="k-m1"></div>
      <div class="kpi-footnote">promedio todas las cohortes</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Retención Mes 3</div>
      <div class="kpi-value md" id="k-m3"></div>
      <div class="kpi-footnote">promedio todas las cohortes</div>
    </div>
  </div>

  <div class="card" style="margin-bottom:20px">
    <div class="card-header">
      <span class="card-title">Retención Promedio por Mes desde Adquisición</span>
      <span class="card-subtitle">% pacientes que repiten cita · promedio de cohortes disponibles</span>
    </div>
    <div class="chart-wrap" style="height:220px"><canvas id="c-ret-line"></canvas></div>
  </div>

  <div class="table-card">
    <div class="card-header">
      <span class="card-title">Heatmap de Cohortes — Retention Rate (%)</span>
      <span class="card-subtitle">M+1 en adelante · cada celda → % de pacientes que regresaron ese mes</span>
    </div>
    <div class="heatmap-outer">
      <table class="heatmap" id="heatmap-table"></table>
    </div>
    <div class="heatmap-legend">
      <span>Bajo</span>
      <div class="legend-gradient"></div>
      <span>Alto</span>
      <span style="margin-left:12px;color:var(--ink-200)">· Sin datos → celda vacía (cohorte reciente)</span>
    </div>
  </div>

  <div class="page-footer">Cohorte = mes de primera cita completada · 666 observaciones · Fuente: dbt_marts.mart_patient_retention</div>
</main>

<!-- ══════════════════════════════════════════════════════════════════════
     PAGE 3 — SPECIALTY PERFORMANCE
     ══════════════════════════════════════════════════════════════════════ -->
<main id="p3" class="page">
  <p class="page-title">Specialty Performance</p>

  <div class="chart-grid">
    <div class="card">
      <div class="card-header">
        <span class="card-title">Revenue por Especialidad</span>
        <span class="card-subtitle">Top 10 · EUR</span>
      </div>
      <div class="chart-wrap"><canvas id="c-sp-revenue"></canvas></div>
    </div>
    <div class="card">
      <div class="card-header">
        <span class="card-title">Tasa de Completado</span>
        <span class="card-subtitle">Top 10 · escala 60–68%</span>
      </div>
      <div class="chart-wrap"><canvas id="c-sp-tasa"></canvas></div>
    </div>
  </div>

  <div class="table-card">
    <div class="card-header">
      <span class="card-title">Rendimiento por Especialidad</span>
      <span class="card-subtitle">20 especialidades · ordenadas por revenue</span>
    </div>
    <table class="data-table">
      <thead>
        <tr>
          <th style="width:40px">#</th>
          <th>Especialidad</th>
          <th>Revenue</th>
          <th>Citas</th>
          <th>Ticket Medio</th>
          <th>Tasa Completado</th>
          <th>Doctores</th>
        </tr>
      </thead>
      <tbody id="sp-tbody"></tbody>
    </table>
  </div>

  <div class="page-footer">Fuente: dbt_marts.agg_specialty_performance · BigQuery EU</div>
</main>

<script>
/* ═══════════════════════════════════════════════════════════════════════
   DATA
   ═══════════════════════════════════════════════════════════════════════ */
const DATA = %%DATA%%;

/* ═══════════════════════════════════════════════════════════════════════
   FORMATTING HELPERS
   ═══════════════════════════════════════════════════════════════════════ */
const fmt  = n => n.toLocaleString('es-ES', { maximumFractionDigits: 0 });
const pct  = n => n.toLocaleString('es-ES', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + '%';
const fmtEur = n => {
  if (n >= 1e6) return '€' + (n / 1e6).toLocaleString('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' M';
  if (n >= 1e3) return '€' + (n / 1e3).toLocaleString('es-ES', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + ' k';
  return '€' + fmt(n);
};

/* ═══════════════════════════════════════════════════════════════════════
   CHART.JS GLOBAL DEFAULTS
   ═══════════════════════════════════════════════════════════════════════ */
Chart.defaults.font.family = "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter', sans-serif";
Chart.defaults.font.size = 11.5;
Chart.defaults.color = '#6b7fa0';
Chart.defaults.plugins.legend.display = false;
Chart.defaults.plugins.tooltip.backgroundColor = '#0d1b2a';
Chart.defaults.plugins.tooltip.titleColor = '#e4eaf2';
Chart.defaults.plugins.tooltip.bodyColor = '#96a7bf';
Chart.defaults.plugins.tooltip.padding = 10;
Chart.defaults.plugins.tooltip.cornerRadius = 6;
Chart.defaults.plugins.tooltip.displayColors = false;
Chart.defaults.plugins.tooltip.titleFont = { size: 12, weight: '600' };
Chart.defaults.plugins.tooltip.bodyFont = { size: 11.5 };
Chart.defaults.scale.grid.color = '#edf1f7';
Chart.defaults.scale.ticks.padding = 6;

const TEAL   = '#14939a';
const TEAL_A = 'rgba(20,147,154,.12)';
const BLUE   = '#3b82f6';
const BLUE_A = 'rgba(59,130,246,.12)';
const GREEN  = '#22a06b';
const GREEN_A= 'rgba(34,160,107,.12)';
const SLATE  = '#243b53';

/* ═══════════════════════════════════════════════════════════════════════
   TAB SWITCHING
   ═══════════════════════════════════════════════════════════════════════ */
function showPage(id, tab) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  tab.classList.add('active');
}

/* ═══════════════════════════════════════════════════════════════════════
   PAGE 1 — KPIs
   ═══════════════════════════════════════════════════════════════════════ */
document.getElementById('k-revenue').textContent = fmtEur(DATA.kpis.revenue);
document.getElementById('k-citas').textContent   = fmt(DATA.kpis.citas);
document.getElementById('k-tasa').textContent    = pct(DATA.kpis.tasa);
document.getElementById('k-conv').textContent    = pct(DATA.kpis.conversion);

/* ── Revenue line chart ─────────────────────────────────────────────── */
const monthLabels = DATA.monthly.map(r => {
  const [y, m] = r.mes.split('-');
  const names = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
  return `${names[+m]} ${y.slice(2)}`;
});

new Chart(document.getElementById('c-revenue'), {
  type: 'line',
  data: {
    labels: monthLabels,
    datasets: [{
      data: DATA.monthly.map(r => r.revenue),
      borderColor: TEAL,
      backgroundColor: ctx => {
        const gradient = ctx.chart.ctx.createLinearGradient(0, 0, 0, ctx.chart.height);
        gradient.addColorStop(0, 'rgba(20,147,154,.18)');
        gradient.addColorStop(1, 'rgba(20,147,154,.00)');
        return gradient;
      },
      borderWidth: 2,
      fill: true,
      tension: 0.38,
      pointRadius: 0,
      pointHoverRadius: 5,
      pointHoverBackgroundColor: TEAL,
      pointHoverBorderColor: '#fff',
      pointHoverBorderWidth: 2,
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      tooltip: {
        callbacks: {
          title: items => items[0].label,
          label: item => '  Revenue: ' + fmtEur(item.raw)
        }
      }
    },
    scales: {
      x: { border: { display: false }, grid: { display: false }, ticks: { maxRotation: 0, maxTicksLimit: 12 } },
      y: {
        border: { display: false },
        ticks: { callback: v => fmtEur(v), maxTicksLimit: 6 }
      }
    }
  }
});

/* ── Appointments bar chart ─────────────────────────────────────────── */
new Chart(document.getElementById('c-citas'), {
  type: 'bar',
  data: {
    labels: monthLabels,
    datasets: [{
      data: DATA.monthly.map(r => r.citas),
      backgroundColor: ctx => {
        const v = ctx.raw;
        const max = Math.max(...DATA.monthly.map(r => r.citas));
        const alpha = 0.35 + 0.65 * (v / max);
        return `rgba(36,59,83,${alpha.toFixed(2)})`;
      },
      borderRadius: 3,
      borderSkipped: false,
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      tooltip: {
        callbacks: {
          title: items => items[0].label,
          label: item => '  Citas: ' + fmt(item.raw)
        }
      }
    },
    scales: {
      x: { border: { display: false }, grid: { display: false }, ticks: { maxRotation: 0, maxTicksLimit: 12 } },
      y: { border: { display: false }, ticks: { callback: v => fmt(v), maxTicksLimit: 6 }, min: 900 }
    }
  }
});

/* ═══════════════════════════════════════════════════════════════════════
   PAGE 2 — RETENTION
   ═══════════════════════════════════════════════════════════════════════ */
document.getElementById('k-m1').textContent = pct(DATA.retention_m1);
document.getElementById('k-m3').textContent = pct(DATA.retention_m3);

/* ── Average retention trend line ───────────────────────────────────── */
const maxMes = Math.max(...DATA.cohort.map(r => r.mes));
const avgByMes = [];
for (let m = 0; m <= maxMes; m++) {
  const rows = DATA.cohort.filter(r => r.mes === m && r.mes > 0); // exclude baseline
  if (m === 0) { avgByMes.push(null); continue; }
  avgByMes.push(rows.length ? +(rows.reduce((s, r) => s + r.ret, 0) / rows.length).toFixed(1) : null);
}

new Chart(document.getElementById('c-ret-line'), {
  type: 'line',
  data: {
    labels: Array.from({ length: maxMes + 1 }, (_, i) => 'M+' + i),
    datasets: [{
      data: avgByMes,
      borderColor: GREEN,
      backgroundColor: ctx => {
        const gradient = ctx.chart.ctx.createLinearGradient(0, 0, 0, ctx.chart.height);
        gradient.addColorStop(0, 'rgba(34,160,107,.18)');
        gradient.addColorStop(1, 'rgba(34,160,107,.00)');
        return gradient;
      },
      borderWidth: 2,
      fill: true,
      tension: 0.38,
      pointRadius: 0,
      pointHoverRadius: 5,
      pointHoverBackgroundColor: GREEN,
      pointHoverBorderColor: '#fff',
      pointHoverBorderWidth: 2,
      spanGaps: true,
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      tooltip: {
        callbacks: {
          label: item => item.raw != null ? '  Retención: ' + pct(item.raw) : ''
        }
      }
    },
    scales: {
      x: { border: { display: false }, grid: { display: false }, ticks: { maxTicksLimit: 12 } },
      y: {
        border: { display: false },
        min: 0,
        ticks: { callback: v => v + '%', maxTicksLimit: 6 }
      }
    }
  }
});

/* ── Cohort heatmap ─────────────────────────────────────────────────── */
(function buildHeatmap() {
  function fmtCohort(s) {
    // s = "2022-01"  →  "01-2022"
    const [y, m] = s.split('-');
    return m + '-' + y;
  }

  const cohorts = [...new Set(DATA.cohort.map(r => r.cohort))].sort();
  const cols = Math.min(maxMes + 1, 13); // columns M+1..M+12 (M+0 excluded)
  const map = {};
  DATA.cohort.forEach(r => { map[r.cohort + '|' + r.mes] = r.ret; });

  // Compute global min/max for non-baseline values to calibrate color scale
  const vals = DATA.cohort.filter(r => r.mes > 0).map(r => r.ret);
  const vMin = Math.min(...vals); // ~2.0
  const vMax = Math.max(...vals); // ~13.3

  // Color scale: light green → medium green → deep green
  function heatColor(v) {
    if (v == null) return { bg: 'transparent', fg: '#96a7bf' };
    const t = Math.max(0, Math.min(1, (v - vMin) / (vMax - vMin)));
    // Interpolate: #e8f5e9 (low) → #66bb6a (mid) → #1b5e20 (high)
    let r, g, b;
    if (t < 0.5) {
      const u = t * 2;
      r = Math.round(232 + (102 - 232) * u);
      g = Math.round(245 + (187 - 245) * u);
      b = Math.round(233 + (106 - 233) * u);
    } else {
      const u = (t - 0.5) * 2;
      r = Math.round(102 + (27  - 102) * u);
      g = Math.round(187 + (94  - 187) * u);
      b = Math.round(106 + (32  - 106) * u);
    }
    const fg = t > 0.45 ? '#ffffff' : '#1b3a1c';
    return { bg: `rgb(${r},${g},${b})`, fg };
  }

  const tbl = document.getElementById('heatmap-table');
  let html = '<thead><tr><th>Cohorte</th>';
  for (let m = 1; m < cols; m++) {
    html += `<th>M+${m}</th>`;
  }
  html += '</tr></thead><tbody>';

  cohorts.forEach(cohort => {
    html += `<tr><td>${fmtCohort(cohort)}</td>`;
    for (let m = 1; m < cols; m++) {
      const v = map[cohort + '|' + m];
      if (v == null) { html += '<td style="background:#f7f9fc"></td>'; continue; }
      const { bg, fg } = heatColor(v);
      html += `<td style="background:${bg};color:${fg}">${v.toLocaleString('es-ES', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%</td>`;
    }
    html += '</tr>';
  });
  html += '</tbody>';
  tbl.innerHTML = html;
})();

/* ═══════════════════════════════════════════════════════════════════════
   PAGE 3 — SPECIALTY PERFORMANCE
   ═══════════════════════════════════════════════════════════════════════ */
const top10 = DATA.specialty.slice(0, 10);

/* ── Revenue horizontal bar ─────────────────────────────────────────── */
new Chart(document.getElementById('c-sp-revenue'), {
  type: 'bar',
  data: {
    labels: top10.map(r => r.nombre),
    datasets: [{
      data: top10.map(r => r.revenue),
      backgroundColor: top10.map((_, i) => `rgba(20,147,154,${1 - i * 0.065})`),
      borderRadius: 4,
      borderSkipped: false,
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    indexAxis: 'y',
    interaction: { mode: 'y', intersect: false },
    plugins: {
      tooltip: {
        callbacks: {
          label: item => '  Revenue: ' + fmtEur(item.raw)
        }
      }
    },
    scales: {
      x: { border: { display: false }, ticks: { callback: v => fmtEur(v), maxTicksLimit: 5 } },
      y: { border: { display: false }, grid: { display: false }, ticks: { font: { size: 11 } } }
    }
  }
});

/* ── Completion rate horizontal bar ─────────────────────────────────── */
new Chart(document.getElementById('c-sp-tasa'), {
  type: 'bar',
  data: {
    labels: top10.map(r => r.nombre),
    datasets: [{
      data: top10.map(r => r.tasa),
      backgroundColor: top10.map(r => {
        const maxT = Math.max(...DATA.specialty.map(s => s.tasa));
        const minT = Math.min(...DATA.specialty.map(s => s.tasa));
        const t = (r.tasa - minT) / (maxT - minT);
        return `rgba(36,59,83,${0.35 + 0.65 * t})`;
      }),
      borderRadius: 4,
      borderSkipped: false,
    }]
  },
  options: {
    responsive: true, maintainAspectRatio: false,
    indexAxis: 'y',
    interaction: { mode: 'y', intersect: false },
    plugins: {
      tooltip: {
        callbacks: {
          label: item => '  Tasa: ' + pct(item.raw)
        }
      }
    },
    scales: {
      x: {
        border: { display: false },
        min: 60, max: 70,
        ticks: { callback: v => v + '%', maxTicksLimit: 6 }
      },
      y: { border: { display: false }, grid: { display: false }, ticks: { font: { size: 11 } } }
    }
  }
});

/* ── Specialty detail table ─────────────────────────────────────────── */
const maxRevenue = Math.max(...DATA.specialty.map(r => r.revenue));
const tbody = document.getElementById('sp-tbody');
tbody.innerHTML = DATA.specialty.map((r, i) => {
  const barWidth = ((r.tasa - 60) / 10 * 100).toFixed(1);
  const isTop = i < 3;
  return `
  <tr>
    <td><span class="rank-badge${isTop ? ' top' : ''}">${i + 1}</span></td>
    <td style="font-weight:500;color:#0d1b2a">${r.nombre}</td>
    <td style="font-variant-numeric:tabular-nums;font-weight:600;color:#0d1b2a">${fmtEur(r.revenue)}</td>
    <td style="font-variant-numeric:tabular-nums">${fmt(r.appts)}</td>
    <td style="font-variant-numeric:tabular-nums">${fmtEur(r.ticket)}</td>
    <td>
      <div class="pct-bar-wrap">
        <div class="pct-bar-track"><div class="pct-bar-fill" style="width:${barWidth}%"></div></div>
        <span style="font-variant-numeric:tabular-nums;min-width:38px;text-align:right">${pct(r.tasa)}</span>
      </div>
    </td>
    <td style="color:#4a6080">${r.doctores}</td>
  </tr>`;
}).join('');
</script>
</body>
</html>
"""

# ── Inject data and write dashboard ───────────────────────────────────────
data_js = json.dumps(data, ensure_ascii=False)
html = HTML_TEMPLATE.replace('%%DATA%%', data_js)

DASHBOARD = Path("dashboards/mediconnect_dashboard.html")
DASHBOARD.parent.mkdir(parents=True, exist_ok=True)
DASHBOARD.write_text(html, encoding="utf-8")
print(f"\nDone -> {DASHBOARD} ({DASHBOARD.stat().st_size // 1024} KB)")
