# Power BI Dashboard Spec — MediConnect Executive Dashboard

## Fuentes de datos

| Tabla BigQuery | Dataset dbt | Uso |
|---|---|---|
| `agg_daily_business_kpis` | `dbt_marts` | Revenue, citas, leads diarios + acumulados |
| `agg_monthly_country_kpis` | `dbt_marts` | Mapa de calor geográfico |
| `agg_specialty_performance` | `dbt_marts` | Tabla de ranking de especialidades |
| `mart_patient_retention` | `dbt_marts` | Tabla de cohortes |
| `mart_appointment_quality` | `dbt_marts` | No-show rate por canal |

**Conexión:** BigQuery connector nativo en Power BI Desktop.
`Obtener datos → Google BigQuery → Proyecto: topd-lab → Dataset: dbt_marts`

---

## Página 1: Executive Overview

### Objetivo
Vista de negocio de alto nivel para C-level. Una pantalla, sin scroll.

### KPI Cards (fila superior)
- **Revenue MTD** — `SUM(daily_revenue_eur)` filtrado al mes actual
- **Citas completadas MTD** — `SUM(completed_appointments)` mes actual
- **Lead conversion rate** — `AVG(lead_conversion_rate)` últimos 30 días
- **No-show rate** — `AVG(1 - completion_rate)` últimos 30 días

Formato: número grande + variación % vs mes anterior (condicional: verde si mejora, rojo si empeora)

### Gráfico de área: Revenue acumulado vs año anterior
- Eje X: fecha (día)
- Eje Y: `cumulative_revenue_eur`
- Dos líneas: año actual (azul) + año anterior (gris punteado)
- Fuente: `agg_daily_business_kpis`

### Gráfico de barras: Citas por canal (últimos 90 días)
- Eje X: canal (web, app, phone, clinic)
- Eje Y: `completed_appointments`
- Color: azul corporate
- Fuente: `mart_appointment_quality` agrupado

### Tabla: Top 5 especialidades por revenue
- Columnas: specialty_name | total_revenue_eur | completion_rate | specialty_revenue_rank
- Ordenada por revenue_rank
- Fuente: `agg_specialty_performance`

---

## Página 2: Geographic Performance

### Mapa de calor
- Tipo: Filled Map (mapa de burbujas sobre países europeos)
- Color: escala de azul según `total_revenue_eur`
- Tooltip: país | revenue | citas | completion_rate
- Fuente: `agg_monthly_country_kpis`

### Gráfico de barras apiladas: Completion rate por país
- Eje X: country_name
- Barras: completed / cancelled / no_show / scheduled
- Fuente: `agg_monthly_country_kpis`

### Filtro de slicers
- Año/Mes (jerarquía de fecha)
- Región (Europa / Latinoamérica)

---

## Página 3: Patient Retention (Cohort Analysis)

### Tabla de cohortes
- Filas: cohort_month
- Columnas: M+0, M+1, M+2, M+3, M+4, M+5
- Valores: `retention_rate` en formato %
- Formato condicional: gradiente de rojo (bajo) a verde (alto)
- Fuente: `mart_patient_retention`

### Línea: Retention rate M+1 a lo largo del tiempo
- Eje X: cohort_month
- Eje Y: retention_rate donde months_since_acquisition = 1
- Objetivo: ver si la retención al primer mes mejora con el tiempo

---

## Medidas DAX clave

Ver [measures_dax.md](measures_dax.md) para el código completo.

```
Revenue MTD = 
CALCULATE(
    SUM(agg_daily_business_kpis[daily_revenue_eur]),
    DATESMTD(agg_daily_business_kpis[date])
)

Revenue MoM % = 
DIVIDE(
    [Revenue MTD] - [Revenue MTD Prev Month],
    [Revenue MTD Prev Month]
)
```

---

## Guía de publicación

1. Power BI Desktop → Publicar → Workspace "MediConnect Analytics"
2. Configurar actualización programada: diaria a las 06:00 UTC
3. Configurar gateway si los datos están on-premise (no aplica para BigQuery directo)
4. Compartir enlace al dashboard con el equipo
