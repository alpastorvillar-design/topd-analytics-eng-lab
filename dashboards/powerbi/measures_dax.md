# Power BI DAX Measures — MediConnect

## ¿Por qué DAX?

DAX (Data Analysis Expressions) es el lenguaje de fórmulas de Power BI.
Las medidas DAX calculan valores en tiempo de consulta, al contrario que
las columnas calculadas que se calculan al refrescar los datos.

**Regla práctica**: transformaciones y agregaciones → en dbt/SQL.
Lógica de presentación, comparativas temporales, filtros dinámicos → en DAX.

---

## Revenue Measures

```dax
-- Revenue total del período seleccionado
Revenue Total =
SUM(agg_daily_business_kpis[daily_revenue_eur])

-- Revenue Month-to-Date (acumula desde el 1 del mes hasta el día seleccionado)
Revenue MTD =
CALCULATE(
    [Revenue Total],
    DATESMTD(agg_daily_business_kpis[date])
)

-- Revenue del mes anterior (para calcular MoM)
Revenue Prev Month =
CALCULATE(
    [Revenue Total],
    PREVIOUSMONTH(agg_daily_business_kpis[date])
)

-- Month-over-Month growth en %
Revenue MoM % =
DIVIDE(
    [Revenue MTD] - [Revenue Prev Month],
    [Revenue Prev Month],
    BLANK()   -- BLANK() si denominador = 0 (equivalente a SAFE_DIVIDE en BQ)
)

-- Revenue Year-to-Date
Revenue YTD =
CALCULATE(
    [Revenue Total],
    DATESYTD(agg_daily_business_kpis[date])
)

-- Revenue mismo período año anterior
Revenue SPLY =
CALCULATE(
    [Revenue Total],
    SAMEPERIODLASTYEAR(agg_daily_business_kpis[date])
)

-- Year-over-Year growth en %
Revenue YoY % =
DIVIDE(
    [Revenue YTD] - [Revenue SPLY],
    [Revenue SPLY],
    BLANK()
)
```

---

## Appointment Measures

```dax
-- Citas completadas
Completed Appointments =
SUMX(
    agg_daily_business_kpis,
    agg_daily_business_kpis[completed_appointments]
)

-- Completion rate
Completion Rate =
DIVIDE(
    [Completed Appointments],
    SUM(agg_daily_business_kpis[total_appointments])
)

-- No-show rate
No-Show Rate =
DIVIDE(
    SUM(agg_daily_business_kpis[no_show_appointments]),
    SUM(agg_daily_business_kpis[total_appointments])
)

-- Nuevos pacientes (primera cita)
New Patients MTD =
CALCULATE(
    SUM(agg_daily_business_kpis[new_patient_appointments]),
    DATESMTD(agg_daily_business_kpis[date])
)
```

---

## Lead Measures

```dax
-- Lead conversion rate
Lead Conversion Rate =
DIVIDE(
    SUM(agg_daily_business_kpis[converted_leads]),
    SUM(agg_daily_business_kpis[total_leads])
)

-- Leads del mes actual
Leads MTD =
CALCULATE(
    SUM(agg_daily_business_kpis[total_leads]),
    DATESMTD(agg_daily_business_kpis[date])
)
```

---

## Formato condicional para KPI cards

```dax
-- Color semáforo para Revenue MoM:
-- verde si > 0, rojo si < 0, gris si BLANK
KPI Color Revenue =
IF(
    ISBLANK([Revenue MoM %]),
    "#808080",                       -- gris
    IF([Revenue MoM %] >= 0,
        "#2ECC71",                   -- verde
        "#E74C3C"                    -- rojo
    )
)

-- Símbolo de flecha para variación
KPI Arrow Revenue =
IF(
    ISBLANK([Revenue MoM %]),
    "—",
    IF([Revenue MoM %] >= 0, "▲", "▼")
)
```

---

## DAX vs dbt/SQL: cuándo usar cada uno

- **dbt/SQL**: transformaciones de datos, joins, limpieza, agregaciones base.
- **DAX**: lógica de presentación dependiente de la selección del usuario:
  comparativas temporales dinámicas (MTD, YTD, MoM), KPIs que cambian
  según los filtros del slicer, medidas derivadas de otras medidas.

**Filter context**: el conjunto de filtros activos cuando se evalúa una medida.
`CALCULATE` lo modifica — es el concepto central de DAX.

**DIVIDE vs /**: `DIVIDE(a, b)` devuelve BLANK si b = 0 (igual que `SAFE_DIVIDE`
en BigQuery). El operador `/` lanza un error. Siempre usar `DIVIDE` en ratios.
