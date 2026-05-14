# Tableau — Calculated Fields Reference

Calculated fields to create inside Tableau when the mart doesn't already have the metric pre-built.
For most KPIs, the marts already have the value — these are for in-viz formatting and drill-down flexibility.

---

## Revenue Metrics

```
// Revenue in EUR (if connecting to fct_payments directly instead of marts)
[amount_cents] / 100.0

// Revenue MoM % change
// Requires a table calc: use "Percent Difference From" on date dimension
// Table Calculation → Percent Difference → Along: month

// Revenue MTD (using LOD)
{ FIXED [appointment_date] : SUM([amount_eur]) }
// Then filter to current month in a date filter
```

---

## Rate Metrics

```
// Completion Rate
SUM(IF [status] = "completed" THEN 1 ELSE 0 END) / COUNT([appointment_id])

// No-Show Rate
SUM(IF [status] = "no_show" THEN 1 ELSE 0 END) / COUNT([appointment_id])

// Cancellation Rate
SUM(IF [status] = "cancelled" THEN 1 ELSE 0 END) / COUNT([appointment_id])

// Lead Conversion Rate
SUM(IF [converted_to_appointment] = TRUE THEN 1 ELSE 0 END) / COUNT([lead_id])
```

---

## Date Helpers

```
// Month label for axis
DATENAME('month', [appointment_date]) + " " + STR(YEAR([appointment_date]))

// Days since appointment (for recency analysis)
DATEDIFF('day', [appointment_date], TODAY())

// Quarter
"Q" + STR(DATEPART('quarter', [appointment_date])) + " " + STR(YEAR([appointment_date]))

// Is current month
DATETRUNC('month', [appointment_date]) = DATETRUNC('month', TODAY())
```

---

## Cohort Retention (Cohort Heatmap)

Used in the Cohort Retention workbook with `mart_patient_retention`.
The mart already has `retention_rate_m1` through `retention_rate_m6`.
Reshape with a parameter to select the month offset:

```
// Dynamic retention column selector
CASE [Month Offset Parameter]
  WHEN 1 THEN [retention_rate_m1]
  WHEN 2 THEN [retention_rate_m2]
  WHEN 3 THEN [retention_rate_m3]
  WHEN 4 THEN [retention_rate_m4]
  WHEN 5 THEN [retention_rate_m5]
  WHEN 6 THEN [retention_rate_m6]
END
```

For the heatmap: Rows = `cohort_month`, Columns = Month Offset (1–6), Color = retention rate.
Mark type: **Square**. Color palette: Sequential (white → blue or white → green).

---

## KPI Color Formatting

```
// Completion rate color (green > 0.75, yellow > 0.60, red otherwise)
IF [Completion Rate] >= 0.75 THEN "good"
ELSEIF [Completion Rate] >= 0.60 THEN "warning"
ELSE "bad"
END

// Revenue vs target (requires a target parameter or seed table)
[Revenue EUR] / [Target Revenue] - 1
```

---

## Doctor Supply/Demand

```
// Supply pressure index (appointments per active doctor)
SUM([total_appointments]) / COUNTD([doctor_id])

// Specialty demand share
SUM([total_appointments]) / TOTAL(SUM([total_appointments]))
```

---

## Tableau vs Power BI — Key Differences in Practice

| Task | Tableau | Power BI |
|------|---------|----------|
| Cohort heatmap | Native with Square marks + color | Matrix visual + conditional formatting |
| YoY % | Table calculation (% diff from) | DAX: `DIVIDE([Revenue], CALCULATE([Revenue], SAMEPERIODLASTYEAR(...)))` |
| Dynamic axis | Parameter + calculated field | DAX field parameters (Power BI Dec 2022+) |
| Row-level security | Data source filters or Tableau Server RLS | Power BI RLS roles |
| Mobile layout | Device-specific layout mode | Phone layout in report view |
| Offline sharing | Packaged workbook (.twbx) | PBIX file (requires Desktop to open) |
| Public sharing | Tableau Public (free) | Publish to web (requires Pro/Premium) |
