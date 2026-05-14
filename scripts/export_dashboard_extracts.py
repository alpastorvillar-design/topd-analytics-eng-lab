"""
export_dashboard_extracts.py

Exporta las tablas mart clave a CSV en data/generated/ para uso en herramientas
BI que no tienen conector nativo de BigQuery (p.ej. Tableau Desktop con CSV).

Ejecutar:
    python scripts/export_dashboard_extracts.py

Los CSVs de salida son gitignoreados (data/generated/).
"""

import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

PROJECT_ID = os.environ["GOOGLE_CLOUD_PROJECT"]
DATASET_ID = os.environ.get("BQ_MARTS_DATASET", "dbt_marts")
LOCATION = os.environ.get("BQ_LOCATION", "EU")
OUTPUT_DIR = Path("data/generated")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

EXPORTS = [
    {
        "table": "agg_daily_business_kpis",
        "description": "Daily KPIs for executive dashboard",
        "filter": "",
    },
    {
        "table": "agg_monthly_country_kpis",
        "description": "Monthly KPIs by country",
        "filter": "",
    },
    {
        "table": "agg_specialty_performance",
        "description": "Monthly performance by specialty",
        "filter": "",
    },
    {
        "table": "mart_patient_retention",
        "description": "Cohort retention analysis",
        "filter": "WHERE months_since_acquisition <= 12",
    },
    {
        "table": "mart_appointment_quality",
        "description": "Appointment quality by channel/specialty/country",
        "filter": "",
    },
]


def export_table(table_name: str, filter_clause: str, description: str) -> None:
    query = f"""
    SELECT *
    FROM `{PROJECT_ID}.{DATASET_ID}.{table_name}`
    {filter_clause}
    """

    print(f"  Exportando {table_name} ({description})...")
    df = client.query(query).to_dataframe()

    out_path = OUTPUT_DIR / f"{table_name}.csv"
    df.to_csv(out_path, index=False)
    print(f"  ✓ {len(df):,} filas → {out_path}")


def main() -> None:
    print(f"Exportando desde {PROJECT_ID}.{DATASET_ID} → {OUTPUT_DIR}/\n")

    for export in EXPORTS:
        export_table(
            table_name=export["table"],
            filter_clause=export["filter"],
            description=export["description"],
        )

    print(f"\n✓ Exportación completada. Archivos en {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
