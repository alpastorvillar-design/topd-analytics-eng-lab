# Tableau — Connection & Setup Guide

## Data Sources

This project connects Tableau to the marts layer in BigQuery.

### Option A — Direct BigQuery Connection (recommended)
Requires Tableau Desktop 2021.4+ or Tableau Cloud.

1. Connect → Google BigQuery
2. Sign in with the Google account that has access to `topd-lab`
3. Project: `topd-lab`
4. Dataset: `dbt_marts`
5. Select the tables you need per workbook (see workbook map below)

### Option B — CSV Extract (no BigQuery license needed)
Run the export script first:
```bash
python scripts/export_dashboard_extracts.py
```
Then connect via Text File to the CSVs in `data/generated/`.
Use joins inside Tableau to replicate the mart structure.

---

## Workbook Map

| Workbook | Primary Table | Supporting Tables |
|----------|--------------|-------------------|
| Executive Overview | `agg_daily_business_kpis` | `dim_countries` |
| Country Drilldown | `agg_monthly_country_kpis` | `dim_countries`, `dim_specialties` |
| Cohort Retention | `mart_patient_retention` | `dim_countries` |
| Doctor Performance | `mart_doctor_supply_demand` | `dim_doctors`, `dim_specialties` |

---

## Published Data Source vs Embedded Connection

| Approach | When to use |
|----------|-------------|
| **Published data source** | Shared across multiple workbooks, centralized refresh schedule |
| **Embedded connection** | Single workbook, ad-hoc analysis |

For this project: embed the connection per workbook (simpler, no Tableau Server required for demos).

---

## Extract vs Live Connection

| Mode | Pros | Cons |
|------|------|------|
| **Live** | Always fresh | Slower on large tables, requires BQ access during presentation |
| **Extract (.hyper)** | Fast, works offline | Needs manual refresh or scheduled extract |

Recommendation: use **Extract** for the retention cohort (large join), **Live** for daily KPIs.

---

## Filters to Add on Every Dashboard

- Date range (using `appointment_date`)
- Country (using `country_id` → `dim_countries.country_name`)
- Specialty (using `specialty_id` → `dim_specialties.specialty_name`)

Set these as Global Filters so they cascade across all sheets in the workbook.

---

## Publishing to Tableau Public

1. File → Save to Tableau Public As...
2. Sign in to your Tableau Public account
3. The workbook uploads with embedded data (extract, not live)
4. Set visibility to Public

> Note: Tableau Public does not support live BigQuery connections.
> Export CSVs first and embed as extract before publishing.
