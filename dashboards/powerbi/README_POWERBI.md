# Power BI — Setup Guide

## Connection

1. Open Power BI Desktop → **Get Data → Google BigQuery**
2. Project: `topd-lab`
3. Dataset filter: `dbt_marts`
4. Select tables: `agg_daily_business_kpis`, `agg_monthly_country_kpis`,
   `agg_specialty_performance`, `mart_patient_retention`, `mart_appointment_quality`

**Authentication**: Google account or service account key (for scheduled refresh via gateway)

## Import vs DirectQuery

| Mode | When to use |
|---|---|
| **Import** | Dev/local — faster, no quota, data snapshot |
| **DirectQuery** | Production dashboard — always live data from BigQuery |

For this project, Import mode is fine since the data is synthetic and updated manually.
For a live production environment, DirectQuery + scheduled refresh is preferred.

## Report Structure

| Page | Source table | Purpose |
|---|---|---|
| Executive Overview | `agg_daily_business_kpis` | Revenue, appointments, leads KPIs |
| Geographic | `agg_monthly_country_kpis` | Country performance comparison |
| Specialty Ranking | `agg_specialty_performance` | Top/bottom specialty table |
| Patient Retention | `mart_patient_retention` | Cohort heatmap |
| Quality | `mart_appointment_quality` | No-show / cancellation by channel |

## Publishing

1. Power BI Desktop → **Publish** → Workspace
2. **Schedule refresh**: Settings → Datasets → Scheduled refresh → Daily 06:00 UTC
3. For BigQuery scheduled refresh you need a **Data Gateway** or use **Service Principal** auth
