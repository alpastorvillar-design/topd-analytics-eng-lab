# MediConnect Analytics Lab

End-to-end Analytics Engineering project built on a synthetic eHealth marketplace dataset.
Covers the full pipeline: data generation in Python → raw ingestion into BigQuery → multi-layer
dbt transformations → BI-ready marts for dashboarding.

---

## Stack

| Layer | Tool |
|---|---|
| Data generation | Python 3.12 + Faker |
| Data warehouse | Google BigQuery |
| Transformations | dbt (BigQuery adapter) |
| BI | Power BI / Metabase |

---

## Project Structure

```
mediconnect-analytics-lab/
├── data/
│   ├── raw/                        # Generated CSVs (gitignored)
│   └── seeds/
├── scripts/
│   ├── generate_synthetic_healthcare_data.py
│   ├── load_to_bigquery.py
│   ├── validate_source_data.py
│   └── export_dashboard_extracts.py
├── sql_practice/
│   ├── 01_joins.sql
│   ├── 02_ctes.sql
│   ├── 03_window_functions.sql
│   ├── 04_bigquery_specific.sql
│   ├── 05_data_quality_queries.sql
│   └── 06_advanced_challenges.sql
├── dbt_mediconnect/
│   ├── models/
│   │   ├── staging/                # Views — 1:1 with raw sources
│   │   ├── intermediate/           # Views — enriched joins, business logic
│   │   └── marts/
│   │       ├── core/               # Tables — dim_* + fct_* (star schema)
│   │       ├── product/            # Tables — retention, quality, supply/demand
│   │       └── executive/          # Tables — daily/monthly/specialty KPIs
│   ├── macros/
│   ├── tests/
│   ├── seeds/
│   └── analyses/
├── dashboards/
│   ├── powerbi/
│   ├── tableau/
│   └── metabase/
└── .env.example
```

---

## Data Model

**Raw sources** (`raw_mediconnect` dataset in BigQuery):
`specialties` · `countries` · `doctors` · `patients` · `appointments` · `payments` · `leads`

**Star schema** (`dbt_marts` dataset):

```
dim_specialties ──┐
dim_countries   ──┤
dim_doctors     ──┼── fct_appointments ──── fct_payments
dim_patients    ──┘        │
                           └── fct_leads
```

**Synthetic data volume**: ~2,000 patients · 300 doctors · 8,000 appointments · ~5,500 payments · 6,000 leads

---

## Setup

### 1. Python environment

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
cp .env.example .env            # Fill in your GCP project details
```

### 2. GCP Service Account

Required IAM roles (minimum privilege):
- `BigQuery Data Editor`
- `BigQuery Job User`
- `BigQuery Read Session User`

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
```

### 3. Generate & load data

```bash
python scripts/generate_synthetic_healthcare_data.py
python scripts/load_to_bigquery.py
python scripts/validate_source_data.py
```

### 4. Run dbt

```bash
cd dbt_mediconnect
cp profiles.yml.example profiles.yml   # add your project_id and key path
dbt deps
dbt debug
dbt run
dbt test
```

---

## dbt Layers

### Staging (views)
Clean raw data: correct types, standardise column names, handle nulls.
One model per source table, no business logic.

### Intermediate (views)
Reusable business logic: enriched joins, window functions (ROW_NUMBER for visit
sequence, LAG for days between visits, RANK for doctor performance ranking),
and derived metrics that multiple marts consume.

### Marts Core (tables, partitioned + clustered)
Star schema: `dim_patients`, `dim_doctors`, `dim_specialties`, `dim_countries`,
`fct_appointments`, `fct_payments`, `fct_leads`.

`fct_appointments` is partitioned by `appointment_date` (MONTH) and clustered
by `[country_id, specialty_id, status]` for cost-efficient queries.

### Marts Product + Executive (tables)
`mart_patient_retention` · `mart_doctor_supply_demand` · `mart_appointment_quality`
`agg_daily_business_kpis` · `agg_monthly_country_kpis` · `agg_specialty_performance`

---

## Cost Control

- Staging as views — no storage cost, always fresh
- Dev variable (`is_dev = true`) limits fact tables to last 90 days in development
- Partitioning on all fact tables by date column
- Clustering on high-cardinality filter columns
- `SELECT col` over `SELECT *` wherever possible

---

## Security

- Service account JSON key is gitignored (`*.json`)
- `.env` is gitignored — use `.env.example` as template
- `data/raw/` gitignored — regenerate with the script
- `profiles.yml` gitignored — use `profiles.yml.example` as template
- Minimum IAM roles only — no BigQuery Admin, no Project Owner
