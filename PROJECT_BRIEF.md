# MediConnect Analytics Lab

End-to-end Analytics Engineering project on a synthetic eHealth marketplace dataset.

## What it covers

A fictional platform where patients book appointments with doctors across 8
countries and 20 medical specialties. The dataset has ~60k appointments, ~15k patients,
500 doctors, ~39k payments and ~100k leads over 3 years (2022-2024),
generated with realistic distributions using Faker. Volumes are calibrated to
exercise partitioning, clustering, incremental models and BI tooling at a scale
closer to a real production marketplace.

The project builds the full data pipeline from scratch:

1. **Data generation** - Python scripts produce raw CSVs with referential integrity,
   realistic date distributions, and controlled no-show / cancellation rates.

2. **Raw ingestion** - Typed load into BigQuery (`raw_mediconnect` dataset) with
   explicit schemas and a 16-check validation suite.

3. **dbt transformations** - Three-layer architecture:
   - Staging: type casting and renaming, materialised as views
   - Intermediate: joins, window functions, business logic (ROW_NUMBER, LAG, RANK)
   - Marts: star schema (4 dims + 3 facts), product analytics, and executive aggregates

4. **BI-ready output** - Partitioned and clustered fact tables feeding Looker Studio
   and a standalone HTML dashboard. Tableau and Power BI specs included as reference.

## Stack

| Layer | Tool |
|-------|------|
| Data generation | Python 3.12 + Faker |
| Data warehouse | Google BigQuery (EU region) |
| Transformations | dbt Core - BigQuery adapter |
| BI | Looker Studio · standalone HTML dashboard |

## Repository structure

```
scripts/            Python: generate, load, validate, export
sql_practice/       SQL patterns and KPI queries against the mart layer
dbt_mediconnect/    dbt project: models, macros, tests, seeds, analyses
dashboards/         Looker Studio screenshots, standalone HTML dashboard, Tableau/PowerBI specs
```

## Running it

```bash
# 1. Generate and load data
python scripts/generate_synthetic_healthcare_data.py
python scripts/load_to_bigquery.py
python scripts/validate_source_data.py

# 2. Build the mart layer
cd dbt_mediconnect
dbt deps && dbt seed && dbt run && dbt test
```

Requires a GCP service account with BigQuery Data Editor + Job User roles,
and credentials set via `GOOGLE_APPLICATION_CREDENTIALS` in `.env`.
