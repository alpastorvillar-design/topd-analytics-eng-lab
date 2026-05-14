# Metabase Dashboard Blueprint — MediConnect

## ¿Por qué Metabase?

Metabase es la herramienta BI open-source más usada en startups y scale-ups.
Conecta directamente con BigQuery y permite crear dashboards sin DAX ni Tableau Desktop.
Ideal para equipos de datos pequeños que quieren mover rápido.

## Conexión con BigQuery

1. **Settings → Databases → Add database → BigQuery**
2. Campos requeridos:
   - Display name: `MediConnect Production`
   - Project ID: `topd-lab`
   - Dataset filters: `dbt_marts` (limitar a sólo los marts, no raw)
   - Service account JSON: pegar el contenido del archivo de clave
3. **Save** → Metabase inicia el sync de tablas (~2 min)

---

## Dashboard 1: Executive Overview

### Pregunta 1: Revenue diario (últimos 90 días)
```
Tabla: agg_daily_business_kpis
Tipo de visual: Line chart
Eje X: date
Eje Y: daily_revenue_eur
Filtro: date >= dateadd(-90 days)
```

### Pregunta 2: KPI Cards resumen del mes
Metabase permite crear "metrics" nativas. Alternativamente, usa queries nativas:

```sql
-- Revenue MTD
SELECT SUM(daily_revenue_eur) AS revenue_mtd
FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH);
```

```sql
-- Completion rate MTD
SELECT
  ROUND(
    SAFE_DIVIDE(
      SUM(completed_appointments),
      SUM(total_appointments)
    ) * 100,
    1
  ) AS completion_rate_pct
FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH);
```

### Pregunta 3: No-show por canal (tabla)
```sql
SELECT
  channel,
  SUM(total_appointments)          AS total,
  SUM(no_show)                     AS no_shows,
  ROUND(
    SAFE_DIVIDE(SUM(no_show), SUM(total_appointments)) * 100,
    1
  )                                AS no_show_rate_pct
FROM `topd-lab.dbt_marts.mart_appointment_quality`
WHERE month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH), MONTH)
GROUP BY channel
ORDER BY no_show_rate_pct DESC;
```

---

## Dashboard 2: Cohort Retention

### Tabla de cohortes (heatmap)

Metabase no tiene un visual de cohort nativo, pero puedes usar una pivot table:

```sql
SELECT
  FORMAT_DATE('%Y-%m', cohort_month)  AS cohort,
  months_since_acquisition            AS months,
  ROUND(retention_rate * 100, 1)      AS retention_pct
FROM `topd-lab.dbt_marts.mart_patient_retention`
WHERE months_since_acquisition <= 5
ORDER BY cohort, months;
```

Visual: Table con conditional formatting (verde > 30%, amarillo 15-30%, rojo < 15%)

---

## Filtros recomendados para los dashboards

- **Filtro de fecha**: conectado a `agg_daily_business_kpis.date`
- **Filtro de país**: conectado a `agg_monthly_country_kpis.country_id`
- **Filtro de especialidad**: conectado a `agg_specialty_performance.specialty_id`

En Metabase, los filtros de dashboard se configuran en "Edit dashboard" → "Add a filter".
Cada pregunta/query debe mapear el filtro a su columna correspondiente.

---

## Actualizaciones automáticas

Metabase tiene caché de queries configurable:
- **Settings → Caching**: activar caché con TTL de 24 horas para queries costosas
- **Pulses** (alertas): notificación por email/Slack si KPI < threshold
  - Ejemplo: alerta si `no_show_rate > 15%` en el día anterior

---

## Metabase vs Power BI

| Dimension | Metabase | Power BI |
|---|---|---|
| Licencia | Open-source / cloud barato | Desktop gratis, Service requiere licencia |
| Curva de aprendizaje | Baja — GUI intuitiva | Media — DAX añade complejidad |
| Queries nativas | SQL directo en UI | Requiere modo experto o DAX |
| BigQuery | Conector nativo | Conector nativo |
| Alertas | Pulses incluidas | Power BI Alerts incluidas |

Para equipos pequeños o MVPs, Metabase es más ágil. Para organizaciones con Microsoft 365
o necesidades avanzadas (composite models, row-level security), Power BI escala mejor.
