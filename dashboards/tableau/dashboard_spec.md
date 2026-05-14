# Tableau Dashboard Spec - MediConnect

## Data Sources

Connect via **Tableau Desktop -> Connect -> Google BigQuery** (or use CSV extracts from `data/generated/`).

| Exported CSV | BQ table equivalent |
|---|---|
| `agg_daily_business_kpis.csv` | Daily revenue + appointments |
| `agg_monthly_country_kpis.csv` | Country breakdown |
| `mart_patient_retention.csv` | Cohort data |

## Dashboard 1: Executive Overview

### KPI Banner
Use **BANs** (Big Ass Numbers) at the top:
- Revenue MTD: `SUM([Daily Revenue Eur])` with date filter = current month
- Completion Rate: `SUM([Completed Appointments]) / SUM([Total Appointments])`
- Lead Conversion Rate: `SUM([Converted Leads]) / SUM([Total Leads])`

### Revenue Line Chart
- Columns: `MONTH([Date])`
- Rows: `SUM([Daily Revenue Eur])`
- Mark type: Line
- Dual axis: add `SUM([Cumulative Revenue Eur])` as secondary axis (area mark)

### Appointments by Status (Stacked Bar)
- Columns: `MONTH([Date])`
- Rows: `SUM([Number of Records])`
- Color: `[Status]`

---

## Dashboard 2: Country Performance

### Filled Map
- Geographic role: `[Country Name]` -> Country/Region
- Color: `SUM([Total Revenue Eur])` - sequential blue palette
- Size: `SUM([Unique Patients])`
- Tooltip: revenue, completion rate, active doctors

### Small Multiples: Completion Rate Trend by Country
- Columns: `[Country Name]`
- Rows: `MONTH([Month])`
- Mark: Line
- Measure: `AVG([Completion Rate])`

---

## Dashboard 3: Cohort Retention Heatmap

The `mart_patient_retention` table has one row per `cohort_month × months_since_acquisition`.

### Setup
- Rows: `[Cohort Month]` (discrete, formatted as YYYY-MM)
- Columns: `[Months Since Acquisition]` (discrete: 0,1,2,3,4,5)
- Mark: Square
- Color: `SUM([Retention Rate])` - diverging palette (red -> green)
- Label: `SUM([Retention Rate])` formatted as percentage

### Calculated Field: Retention %
```
STR(ROUND([Retention Rate] * 100, 1)) + "%"
```

---

## Tableau vs Power BI for this use case

| Dimension | Tableau | Power BI |
|---|---|---|
| BigQuery connector | Native (Tableau Online) | Native (Power BI Service) |
| Custom calculations | Calculated fields | DAX measures |
| Cohort heatmap | Easy with square marks | Requires matrix + conditional format |
| Cost | Tableau Desktop (paid) | Power BI Desktop (free) |
| Sharing | Tableau Online / Public | Power BI Service |

For this dataset, either tool works well. Power BI has more accessible licensing
for personal use; Tableau has better native support for complex custom visualisations.
