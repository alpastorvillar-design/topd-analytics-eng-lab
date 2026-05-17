"""
load_to_bigquery.py

Carga los CSVs de data/raw/ al dataset raw_mediconnect en BigQuery.
Recrea las tablas con esquema explícito para garantizar tipos correctos.

Ejecutar:
    python scripts/load_to_bigquery.py

Requiere:
    - Variable GOOGLE_APPLICATION_CREDENTIALS apuntando al JSON de la SA, O
    - Variable GOOGLE_CLOUD_PROJECT + autenticación via gcloud CLI
    - pip install google-cloud-bigquery pyarrow pandas python-dotenv
"""

import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

PROJECT_ID = os.environ["GOOGLE_CLOUD_PROJECT"]
DATASET_ID = os.environ.get("BQ_RAW_DATASET", "raw_mediconnect")
LOCATION = os.environ.get("BQ_LOCATION", "EU")
DATA_DIR = Path("data/raw")

client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

# ── Esquemas explícitos 
# BigQuery infiere bien los tipos desde Parquet/Arrow, pero los definimos
# explícitamente para garantizar que STRING no se convierta en INT64
# y que los campos nullable sean NULLABLE (no REQUIRED).

SCHEMAS = {
    "specialties": [
        bigquery.SchemaField("specialty_id",    "STRING",    "REQUIRED"),
        bigquery.SchemaField("specialty_name",  "STRING",    "REQUIRED"),
        bigquery.SchemaField("specialty_group", "STRING",    "REQUIRED"),
    ],
    "countries": [
        bigquery.SchemaField("country_id",   "STRING", "REQUIRED"),
        bigquery.SchemaField("country_name", "STRING", "REQUIRED"),
        bigquery.SchemaField("region",       "STRING", "REQUIRED"),
        bigquery.SchemaField("currency",     "STRING", "REQUIRED"),
    ],
    "doctors": [
        bigquery.SchemaField("doctor_id",               "STRING",    "REQUIRED"),
        bigquery.SchemaField("full_name",               "STRING",    "REQUIRED"),
        bigquery.SchemaField("specialty_id",            "STRING",    "REQUIRED"),
        bigquery.SchemaField("country_id",              "STRING",    "REQUIRED"),
        bigquery.SchemaField("city",                    "STRING",    "REQUIRED"),
        bigquery.SchemaField("created_at",              "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("is_active",               "BOOL",      "REQUIRED"),
        bigquery.SchemaField("rating",                  "FLOAT64",   "REQUIRED"),
        bigquery.SchemaField("years_experience",        "INT64",     "REQUIRED"),
        bigquery.SchemaField("accepts_online_booking",  "BOOL",      "REQUIRED"),
    ],
    "patients": [
        bigquery.SchemaField("patient_id",           "STRING",    "REQUIRED"),
        bigquery.SchemaField("full_name",            "STRING",    "REQUIRED"),
        bigquery.SchemaField("gender",               "STRING",    "REQUIRED"),
        bigquery.SchemaField("birth_date",           "DATE",      "REQUIRED"),
        bigquery.SchemaField("country_id",           "STRING",    "REQUIRED"),
        bigquery.SchemaField("city",                 "STRING",    "REQUIRED"),
        bigquery.SchemaField("created_at",           "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("acquisition_channel",  "STRING",    "REQUIRED"),
        bigquery.SchemaField("is_active",            "BOOL",      "REQUIRED"),
    ],
    "appointments": [
        bigquery.SchemaField("appointment_id",          "STRING",    "REQUIRED"),
        bigquery.SchemaField("patient_id",              "STRING",    "REQUIRED"),
        bigquery.SchemaField("doctor_id",               "STRING",    "REQUIRED"),
        bigquery.SchemaField("appointment_created_at",  "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("appointment_start_at",    "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("updated_at",              "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("status",                  "STRING",    "REQUIRED"),
        bigquery.SchemaField("channel",                 "STRING",    "REQUIRED"),
        bigquery.SchemaField("cancellation_reason",     "STRING",    "NULLABLE"),
        bigquery.SchemaField("is_first_appointment",    "BOOL",      "REQUIRED"),
        bigquery.SchemaField("source_lead_id",          "STRING",    "NULLABLE"),
    ],
    "payments": [
        bigquery.SchemaField("payment_id",          "STRING",    "REQUIRED"),
        bigquery.SchemaField("appointment_id",      "STRING",    "REQUIRED"),
        bigquery.SchemaField("patient_id",          "STRING",    "REQUIRED"),
        bigquery.SchemaField("doctor_id",           "STRING",    "REQUIRED"),
        bigquery.SchemaField("payment_created_at",  "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("updated_at",          "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("amount_cents",        "INT64",     "REQUIRED"),
        bigquery.SchemaField("currency",            "STRING",    "REQUIRED"),
        bigquery.SchemaField("payment_status",      "STRING",    "REQUIRED"),
        bigquery.SchemaField("payment_method",      "STRING",    "REQUIRED"),
    ],
    "leads": [
        bigquery.SchemaField("lead_id",                    "STRING",    "REQUIRED"),
        bigquery.SchemaField("patient_id",                 "STRING",    "NULLABLE"),
        bigquery.SchemaField("doctor_id",                  "STRING",    "NULLABLE"),
        bigquery.SchemaField("specialty_id",               "STRING",    "REQUIRED"),
        bigquery.SchemaField("country_id",                 "STRING",    "REQUIRED"),
        bigquery.SchemaField("created_at",                 "TIMESTAMP", "REQUIRED"),
        bigquery.SchemaField("lead_source",                "STRING",    "REQUIRED"),
        bigquery.SchemaField("lead_status",                "STRING",    "REQUIRED"),
        bigquery.SchemaField("converted_appointment_id",   "STRING",    "NULLABLE"),
    ],
}

# Orden de carga respeta integridad referencial:
# primero dimensiones, luego hechos
LOAD_ORDER = [
    "specialties",
    "countries",
    "doctors",
    "patients",
    "appointments",
    "payments",
    "leads",
]


def ensure_dataset() -> None:
    dataset_ref = bigquery.Dataset(f"{PROJECT_ID}.{DATASET_ID}")
    dataset_ref.location = LOCATION
    client.create_dataset(dataset_ref, exists_ok=True)
    print(f"Dataset {DATASET_ID} listo en {LOCATION}")


def load_table(table_name: str) -> None:
    csv_path = DATA_DIR / f"{table_name}.csv"
    if not csv_path.exists():
        print(f"  ⚠ No encontrado: {csv_path}  (skipping)")
        return

    df = pd.read_csv(csv_path)

    # Convertir columnas al tipo correcto segun el schema antes de subir a BQ
    for field in SCHEMAS[table_name]:
        if field.name not in df.columns:
            continue
        if field.field_type == "TIMESTAMP":
            df[field.name] = pd.to_datetime(df[field.name], utc=True)
        elif field.field_type == "DATE":
            df[field.name] = pd.to_datetime(df[field.name]).dt.date
        elif field.field_type == "BOOL":
            df[field.name] = df[field.name].astype(bool)
        elif field.field_type == "INT64":
            df[field.name] = pd.to_numeric(df[field.name], errors="coerce").astype("Int64")
        elif field.field_type == "FLOAT64":
            df[field.name] = pd.to_numeric(df[field.name], errors="coerce")

    print(f"  Cargando {table_name}: {len(df):,} filas...")

    table_ref = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    schema = SCHEMAS[table_name]

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        # WRITE_TRUNCATE: borra y recrea la tabla en cada carga.
        # Ideal para datos sintéticos que se regeneran completos.
        # En producción, usarías WRITE_APPEND o merge jobs.
    )

    load_job = client.load_table_from_dataframe(
        df, table_ref, job_config=job_config
    )
    load_job.result()  # bloquea hasta que termine
    print(f"   {table_name}: {load_job.output_rows:,} filas cargadas")


def main() -> None:
    print(f"Proyecto: {PROJECT_ID}")
    print(f"Dataset:  {DATASET_ID}\n")

    ensure_dataset()

    for table_name in LOAD_ORDER:
        load_table(table_name)

    print("\n Carga completada.")
    print(f"  Puedes ver las tablas en: https://console.cloud.google.com/bigquery?project={PROJECT_ID}")


if __name__ == "__main__":
    main()
