# Looker Studio - Dashboard Guide

## Purpose

Looker Studio is the live BI layer for the MediConnect Analytics Engineering Lab. It connects to the BigQuery marts produced by dbt and provides a shareable business dashboard for non-technical stakeholders.

## Data Sources

| BigQuery table | Use |
|---|---|
| `dbt_marts.agg_daily_business_kpis` | Executive KPIs, revenue trend, appointment trend, lead conversion |
| `dbt_marts.agg_monthly_country_kpis` | Country and regional performance |
| `dbt_marts.agg_specialty_performance` | Specialty ranking and completion rate |
| `dbt_marts.mart_patient_retention` | Cohort retention heatmap |
| `dbt_marts.mart_appointment_quality` | No-show, cancellation, completion quality |

## Report Pages

| Page | Main question | Primary tables |
|---|---|---|
| Executive Overview | Is the marketplace growing and converting demand into completed appointments? | `agg_daily_business_kpis`, `agg_specialty_performance` |
| Country Performance | Which countries drive volume, revenue, and quality? | `agg_monthly_country_kpis` |
| Specialty Performance | Which specialties generate the most revenue and operational efficiency? | `agg_specialty_performance`, `mart_appointment_quality` |
| Operations Quality | Where do no-shows, cancellations, and completion rates need attention? | `mart_appointment_quality` |

## Recommended Controls

- Date range control using `date` or `month`, depending on the page.
- Country filter for country-level pages.
- Specialty filter for specialty and quality pages.
- Channel filter for appointment quality analysis.

## Portfolio Evidence

Screenshots are stored in `dashboards/looker_studio/screenshots/`:

- `01_executive_overview.png`
- `02_country_performance.png`
- `03_specialty_performance.png`
- `04_operations_quality.png`

These screenshots demonstrate the final consumer layer of the dbt marts. For an interview walkthrough, pair them with the dbt DAG and a BigQuery schema screenshot to show the full path from raw data to dashboard.
