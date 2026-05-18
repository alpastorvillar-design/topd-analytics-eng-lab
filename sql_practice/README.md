# SQL Practice

SQL queries against the MediConnect mart layer (`topd-lab.dbt_marts`).
All files are runnable directly in the BigQuery console.

| File | Topics |
|------|--------|
| `00_bigquery_smoke_test.sql` | Row counts, date ranges, FK integrity, partition metadata |
| `01_joins.sql` | INNER, LEFT, FULL OUTER, SELF, anti-join |
| `02_ctes.sql` | CTEs vs subqueries, chained CTEs, NOT EXISTS, date spine, QUALIFY |
| `03_window_functions.sql` | ROW_NUMBER, RANK/DENSE_RANK, LAG/LEAD, SUM OVER frames, NTILE, QUALIFY |
| `04_bigquery_specific.sql` | COUNTIF, SAFE_DIVIDE, QUALIFY, DATE_TRUNC/DIFF, UNNEST, partition pruning |
| `05_data_quality_queries.sql` | PK uniqueness, FK integrity, accepted values, NULL audit, business rules |
| `06_advanced_challenges.sql` | Top-N per group, N-th rank, set diff, % of total, funnel, 90d return rate |
| `07_kpis_and_metrics.sql` | Revenue MoM/YoY/MTD/YTD, LTV, conversion funnel, cohort retention, supply/demand |
| `08_advanced_patterns.sql` | PIVOT/UNPIVOT, ARRAY_AGG, STRUCT, APPROX functions, recursive CTEs, STRING_AGG |
| `09_query_optimization.sql` | Partition pruning, clustering, SELECT *, correlated subqueries, materialisation strategy |
| `10_bigquery_cost_and_monitoring.sql` | INFORMATION_SCHEMA jobs, daily spend, partition pruning comparison, dry-run estimation |

## Dataset structure

```
topd-lab
└── dbt_marts
    ├── dim_patients
    ├── dim_doctors
    ├── dim_specialties
    ├── dim_countries
    ├── fct_appointments        ← partitioned by month, clustered by country/specialty/status
    ├── fct_payments            ← partitioned by month
    ├── fct_leads
    ├── mart_patient_retention
    ├── mart_doctor_supply_demand
    ├── mart_appointment_quality
    ├── agg_daily_business_kpis
    ├── agg_monthly_country_kpis
    └── agg_specialty_performance
```
