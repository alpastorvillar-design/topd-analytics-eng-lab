"""
validate_source_data.py

Valida la calidad de los datos en BigQuery antes de ejecutar dbt.
Comprueba integridad referencial, nulos en campos obligatorios y rangos.

Ejecutar:
    python scripts/validate_source_data.py

Una validación fallida imprime un WARNING pero no lanza excepción,
para que puedas revisar todos los problemas a la vez.
"""

import os
from dataclasses import dataclass, field
from typing import Optional

from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

PROJECT_ID = os.environ["GOOGLE_CLOUD_PROJECT"]
DATASET_ID = os.environ.get("BQ_RAW_DATASET", "raw_mediconnect")
LOCATION = os.environ.get("BQ_LOCATION", "EU")

client = bigquery.Client(project=PROJECT_ID, location=LOCATION)


@dataclass
class Check:
    name: str
    sql: str
    description: str
    expect_zero_rows: bool = True  # la query devuelve filas problemáticas


@dataclass
class CheckResult:
    check: Check
    row_count: int
    passed: bool
    sample_rows: list = field(default_factory=list)


def run_check(check: Check) -> CheckResult:
    query = f"""
    SELECT COUNT(*) AS n
    FROM ({check.sql})
    """
    # Para el sample, ejecutamos la query original limitada
    sample_job = client.query(f"{check.sql} LIMIT 5")
    sample_rows = list(sample_job.result())

    count_job = client.query(query)
    row = list(count_job.result())[0]
    n = row["n"]

    passed = (n == 0) if check.expect_zero_rows else (n > 0)
    return CheckResult(check=check, row_count=n, passed=passed, sample_rows=sample_rows)


# ── Definición de checks ──────────────────────────────────────────────────────

def make_checks(ds: str) -> list[Check]:
    return [
        # ── Unicidad de PKs ───────────────────────────────────────────────
        Check(
            name="pk_specialties_unique",
            description="specialty_id debe ser único",
            sql=f"""
                SELECT specialty_id, COUNT(*) AS n
                FROM `{ds}.specialties`
                GROUP BY specialty_id
                HAVING n > 1
            """,
        ),
        Check(
            name="pk_doctors_unique",
            description="doctor_id debe ser único",
            sql=f"""
                SELECT doctor_id, COUNT(*) AS n
                FROM `{ds}.doctors`
                GROUP BY doctor_id
                HAVING n > 1
            """,
        ),
        Check(
            name="pk_patients_unique",
            description="patient_id debe ser único",
            sql=f"""
                SELECT patient_id, COUNT(*) AS n
                FROM `{ds}.patients`
                GROUP BY patient_id
                HAVING n > 1
            """,
        ),
        Check(
            name="pk_appointments_unique",
            description="appointment_id debe ser único",
            sql=f"""
                SELECT appointment_id, COUNT(*) AS n
                FROM `{ds}.appointments`
                GROUP BY appointment_id
                HAVING n > 1
            """,
        ),
        Check(
            name="pk_payments_unique",
            description="payment_id debe ser único",
            sql=f"""
                SELECT payment_id, COUNT(*) AS n
                FROM `{ds}.payments`
                GROUP BY payment_id
                HAVING n > 1
            """,
        ),

        # ── Integridad referencial ────────────────────────────────────────
        Check(
            name="fk_appointments_patient",
            description="Todas las citas deben tener un patient_id válido",
            sql=f"""
                SELECT a.appointment_id
                FROM `{ds}.appointments` a
                LEFT JOIN `{ds}.patients` p USING (patient_id)
                WHERE p.patient_id IS NULL
            """,
        ),
        Check(
            name="fk_appointments_doctor",
            description="Todas las citas deben tener un doctor_id válido",
            sql=f"""
                SELECT a.appointment_id
                FROM `{ds}.appointments` a
                LEFT JOIN `{ds}.doctors` d USING (doctor_id)
                WHERE d.doctor_id IS NULL
            """,
        ),
        Check(
            name="fk_payments_appointment",
            description="Todos los pagos deben referenciar una cita existente",
            sql=f"""
                SELECT p.payment_id
                FROM `{ds}.payments` p
                LEFT JOIN `{ds}.appointments` a USING (appointment_id)
                WHERE a.appointment_id IS NULL
            """,
        ),
        Check(
            name="payments_only_for_completed",
            description="Los pagos sólo deben existir para citas completed",
            sql=f"""
                SELECT p.payment_id, a.status
                FROM `{ds}.payments` p
                JOIN `{ds}.appointments` a USING (appointment_id)
                WHERE a.status != 'completed'
            """,
        ),

        # ── Valores aceptados ─────────────────────────────────────────────
        Check(
            name="appointment_status_values",
            description="appointment.status debe ser uno de: completed, cancelled, no_show, scheduled",
            sql=f"""
                SELECT DISTINCT status
                FROM `{ds}.appointments`
                WHERE status NOT IN ('completed', 'cancelled', 'no_show', 'scheduled')
            """,
        ),
        Check(
            name="payment_status_values",
            description="payment.payment_status debe ser: paid, refunded, failed, pending",
            sql=f"""
                SELECT DISTINCT payment_status
                FROM `{ds}.payments`
                WHERE payment_status NOT IN ('paid', 'refunded', 'failed', 'pending')
            """,
        ),
        Check(
            name="lead_status_values",
            description="lead.lead_status debe ser: new, contacted, lost, converted",
            sql=f"""
                SELECT DISTINCT lead_status
                FROM `{ds}.leads`
                WHERE lead_status NOT IN ('new', 'contacted', 'lost', 'converted')
            """,
        ),

        # ── Rangos y coherencia temporal ──────────────────────────────────
        Check(
            name="payment_amount_positive",
            description="amount_cents debe ser > 0",
            sql=f"""
                SELECT payment_id, amount_cents
                FROM `{ds}.payments`
                WHERE amount_cents <= 0
            """,
        ),
        Check(
            name="appointment_created_before_start",
            description="appointment_created_at debe ser anterior a appointment_start_at",
            sql=f"""
                SELECT appointment_id, appointment_created_at, appointment_start_at
                FROM `{ds}.appointments`
                WHERE appointment_created_at >= appointment_start_at
            """,
        ),

        # ── Conteos esperados (no-zero checks) ────────────────────────────
        Check(
            name="row_count_specialties",
            description="Debe haber exactamente 20 especialidades",
            sql=f"""
                SELECT COUNT(*) AS n
                FROM `{ds}.specialties`
                HAVING COUNT(*) != 20
            """,
        ),
        Check(
            name="row_count_doctors",
            description="Debe haber 300 médicos",
            sql=f"""
                SELECT COUNT(*) AS n
                FROM `{ds}.doctors`
                HAVING COUNT(*) != 300
            """,
        ),
        Check(
            name="row_count_patients",
            description="Debe haber 2000 pacientes",
            sql=f"""
                SELECT COUNT(*) AS n
                FROM `{ds}.patients`
                HAVING COUNT(*) != 2000
            """,
        ),
        Check(
            name="row_count_appointments",
            description="Debe haber 8000 citas",
            sql=f"""
                SELECT COUNT(*) AS n
                FROM `{ds}.appointments`
                HAVING COUNT(*) != 8000
            """,
        ),
    ]


def main() -> None:
    ds = f"{PROJECT_ID}.{DATASET_ID}"
    print(f"Validando {ds}...\n")

    checks = make_checks(ds)
    results: list[CheckResult] = []

    for check in checks:
        print(f"  [{check.name}]", end=" ")
        try:
            result = run_check(check)
            status = "PASS" if result.passed else "FAIL"
            print(f"{status}  ({result.row_count} filas problemáticas)")
            if not result.passed and result.sample_rows:
                print(f"    Muestra: {result.sample_rows[0]}")
            results.append(result)
        except Exception as e:
            print(f"ERROR: {e}")

    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    print(f"\n{'─' * 50}")
    print(f"Resultado: {passed} PASS / {failed} FAIL")

    if failed > 0:
        print("\nChecks fallidos:")
        for r in results:
            if not r.passed:
                print(f"  ✗ {r.check.name}: {r.check.description}")
        raise SystemExit(1)
    else:
        print("\n✓ Todos los checks pasan. Listo para dbt run.")


if __name__ == "__main__":
    main()
