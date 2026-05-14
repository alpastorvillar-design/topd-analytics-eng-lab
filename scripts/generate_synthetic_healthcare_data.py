"""
generate_synthetic_healthcare_data.py

Genera datos sintéticos realistas para el marketplace eHealth MediConnect.
Produce 7 CSVs en data/raw/ con integridad referencial garantizada.

Volumen: ~2000 pacientes, ~300 médicos, ~8000 citas, ~5500 pagos, ~6000 leads.

Ejecutar:
    python scripts/generate_synthetic_healthcare_data.py

Requiere:
    pip install faker pandas python-dotenv
"""

import random
import os
from datetime import datetime, timedelta, date
from pathlib import Path

import pandas as pd
from faker import Faker

# Semilla para reproducibilidad: los datos serán iguales en cada ejecución
random.seed(42)
fake = Faker('es_ES')
fake.seed_instance(42)

OUTPUT_DIR = Path("data/raw")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Parámetros de volumen ────────────────────────────────────────────────────
N_SPECIALTIES = 20
N_COUNTRIES = 8
N_DOCTORS = 300
N_PATIENTS = 2000
N_APPOINTMENTS = 8000
N_LEADS = 6000

DATE_START = date(2022, 1, 1)
DATE_END = date(2024, 12, 31)


def random_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def random_ts(start: date, end: date) -> datetime:
    d = random_date(start, end)
    return datetime(d.year, d.month, d.day,
                    random.randint(8, 20), random.randint(0, 59))


# ── 1. SPECIALTIES ───────────────────────────────────────────────────────────
print("Generando specialties...")

specialty_names = [
    ("Cardiología", "Medicina interna"),
    ("Dermatología", "Medicina estética"),
    ("Traumatología", "Cirugía"),
    ("Pediatría", "Medicina general"),
    ("Ginecología", "Obstetricia"),
    ("Neurología", "Medicina interna"),
    ("Oftalmología", "Cirugía"),
    ("Psiquiatría", "Salud mental"),
    ("Oncología", "Medicina interna"),
    ("Endocrinología", "Medicina interna"),
    ("Urología", "Cirugía"),
    ("Reumatología", "Medicina interna"),
    ("Neumología", "Medicina interna"),
    ("Gastroenterología", "Medicina interna"),
    ("Otorrinolaringología", "Cirugía"),
    ("Cirugía plástica", "Cirugía"),
    ("Medicina estética", "Medicina estética"),
    ("Nutrición", "Medicina general"),
    ("Fisioterapia", "Rehabilitación"),
    ("Psicología", "Salud mental"),
]

specialties = []
for i, (name, group) in enumerate(specialty_names, 1):
    specialties.append({
        "specialty_id": f"SPE{i:03d}",
        "specialty_name": name,
        "specialty_group": group,
    })

df_specialties = pd.DataFrame(specialties)
df_specialties.to_csv(OUTPUT_DIR / "specialties.csv", index=False)
print(f"  → {len(df_specialties)} specialties")

specialty_ids = df_specialties["specialty_id"].tolist()


# ── 2. COUNTRIES ─────────────────────────────────────────────────────────────
print("Generando countries...")

countries_data = [
    ("ES", "España", "Europa", "EUR"),
    ("GB", "Reino Unido", "Europa", "GBP"),
    ("IT", "Italia", "Europa", "EUR"),
    ("DE", "Alemania", "Europa", "EUR"),
    ("FR", "Francia", "Europa", "EUR"),
    ("MX", "México", "Latinoamérica", "MXN"),
    ("CO", "Colombia", "Latinoamérica", "COP"),
    ("PT", "Portugal", "Europa", "EUR"),
]

countries = [
    {"country_id": cid, "country_name": name, "region": region, "currency": currency}
    for cid, name, region, currency in countries_data
]

df_countries = pd.DataFrame(countries)
df_countries.to_csv(OUTPUT_DIR / "countries.csv", index=False)
print(f"  → {len(df_countries)} countries")

country_ids = df_countries["country_id"].tolist()
country_currencies = dict(zip(df_countries["country_id"], df_countries["currency"]))


# ── 3. DOCTORS ───────────────────────────────────────────────────────────────
print("Generando doctors...")

doctors = []
for i in range(1, N_DOCTORS + 1):
    country = random.choice(country_ids)
    created = random_date(date(2020, 1, 1), date(2022, 12, 31))
    doctors.append({
        "doctor_id": f"DOC{i:04d}",
        "full_name": fake.name(),
        "specialty_id": random.choice(specialty_ids),
        "country_id": country,
        "city": fake.city(),
        "created_at": datetime(created.year, created.month, created.day, 9, 0),
        "is_active": random.random() > 0.05,  # 95% activos
        "rating": round(random.uniform(3.5, 5.0), 1),
        "years_experience": random.randint(2, 30),
        "accepts_online_booking": random.random() > 0.2,
    })

df_doctors = pd.DataFrame(doctors)
df_doctors.to_csv(OUTPUT_DIR / "doctors.csv", index=False)
print(f"  → {len(df_doctors)} doctors")

doctor_ids = df_doctors["doctor_id"].tolist()
doctor_info = df_doctors.set_index("doctor_id")[["specialty_id", "country_id"]].to_dict("index")


# ── 4. PATIENTS ──────────────────────────────────────────────────────────────
print("Generando patients...")

acquisition_channels = ["seo", "sem", "direct", "referral", "social", "email"]
channel_weights = [0.30, 0.20, 0.15, 0.15, 0.12, 0.08]

patients = []
for i in range(1, N_PATIENTS + 1):
    country = random.choice(country_ids)
    birth = random_date(date(1950, 1, 1), date(2005, 12, 31))
    created = random_date(date(2021, 1, 1), date(2024, 6, 30))
    patients.append({
        "patient_id": f"PAT{i:05d}",
        "full_name": fake.name(),
        "gender": random.choice(["M", "F", "M", "F", "other"]),
        "birth_date": birth,
        "country_id": country,
        "city": fake.city(),
        "created_at": datetime(created.year, created.month, created.day, 10, 0),
        "acquisition_channel": random.choices(acquisition_channels, channel_weights)[0],
        "is_active": random.random() > 0.10,
    })

df_patients = pd.DataFrame(patients)
df_patients.to_csv(OUTPUT_DIR / "patients.csv", index=False)
print(f"  → {len(df_patients)} patients")

patient_ids = df_patients["patient_id"].tolist()
patient_created = dict(zip(df_patients["patient_id"], df_patients["created_at"]))


# ── 5. APPOINTMENTS ──────────────────────────────────────────────────────────
print("Generando appointments...")

# Distribución realista de estados
status_choices = ["completed", "cancelled", "no_show", "scheduled"]
status_weights = [0.65, 0.15, 0.10, 0.10]

channels = ["web", "app", "phone", "clinic"]
channel_appt_weights = [0.40, 0.35, 0.15, 0.10]

cancellation_reasons = [
    "patient_cancelled", "doctor_unavailable", "emergency",
    "rescheduled", "no_reason_given"
]

appointments = []
patient_appointment_count = {pid: 0 for pid in patient_ids}

for i in range(1, N_APPOINTMENTS + 1):
    patient_id = random.choice(patient_ids)
    doctor_id = random.choice(doctor_ids)
    doc = doctor_info[doctor_id]

    # Fecha de inicio de cita
    start_at = random_ts(DATE_START, DATE_END)
    # Creación de la cita: entre 1 y 14 días antes
    created_at = start_at - timedelta(days=random.randint(1, 14))

    status = random.choices(status_choices, status_weights)[0]

    # is_first_appointment basado en historial real
    is_first = patient_appointment_count[patient_id] == 0
    patient_appointment_count[patient_id] += 1

    appt = {
        "appointment_id": f"APT{i:06d}",
        "patient_id": patient_id,
        "doctor_id": doctor_id,
        "appointment_created_at": created_at,
        "appointment_start_at": start_at,
        "updated_at": start_at + timedelta(hours=random.randint(1, 48)),
        "status": status,
        "channel": random.choices(channels, channel_appt_weights)[0],
        "cancellation_reason": (
            random.choice(cancellation_reasons)
            if status == "cancelled" else None
        ),
        "is_first_appointment": is_first,
        "source_lead_id": None,  # se rellena después con leads
    }
    appointments.append(appt)

df_appointments = pd.DataFrame(appointments)
df_appointments.to_csv(OUTPUT_DIR / "appointments.csv", index=False)
print(f"  → {len(df_appointments)} appointments")

completed_appt_ids = df_appointments[
    df_appointments["status"] == "completed"
]["appointment_id"].tolist()


# ── 6. PAYMENTS ──────────────────────────────────────────────────────────────
print("Generando payments...")

payment_methods = ["credit_card", "debit_card", "bank_transfer", "paypal"]
method_weights = [0.45, 0.25, 0.20, 0.10]

# Precios por especialidad (en céntimos de EUR)
specialty_price_range = {
    "SPE001": (8000, 25000),   # Cardiología
    "SPE002": (5000, 15000),   # Dermatología
    "SPE003": (9000, 30000),   # Traumatología
    "SPE004": (4000, 12000),   # Pediatría
    "SPE005": (7000, 20000),   # Ginecología
}
default_price_range = (3000, 20000)

payments = []
appt_doctor = dict(zip(df_appointments["appointment_id"], df_appointments["doctor_id"]))

for i, appt_id in enumerate(completed_appt_ids, 1):
    doctor_id = appt_doctor[appt_id]
    specialty = doctor_info[doctor_id]["specialty_id"]
    country = doctor_info[doctor_id]["country_id"]

    price_min, price_max = specialty_price_range.get(specialty, default_price_range)
    amount = random.randint(price_min, price_max)

    appt_row = df_appointments[df_appointments["appointment_id"] == appt_id].iloc[0]
    payment_ts = appt_row["appointment_start_at"] + timedelta(hours=random.randint(1, 24))

    # 85% pagado, 8% reembolsado, 5% fallido, 2% pendiente
    pay_status = random.choices(
        ["paid", "refunded", "failed", "pending"],
        [0.85, 0.08, 0.05, 0.02]
    )[0]

    payments.append({
        "payment_id": f"PAY{i:06d}",
        "appointment_id": appt_id,
        "patient_id": appt_row["patient_id"],
        "doctor_id": doctor_id,
        "payment_created_at": payment_ts,
        "updated_at": payment_ts + timedelta(hours=random.randint(0, 6)),
        "amount_cents": amount,
        "currency": country_currencies.get(country, "EUR"),
        "payment_status": pay_status,
        "payment_method": random.choices(payment_methods, method_weights)[0],
    })

df_payments = pd.DataFrame(payments)
df_payments.to_csv(OUTPUT_DIR / "payments.csv", index=False)
print(f"  → {len(df_payments)} payments")


# ── 7. LEADS ─────────────────────────────────────────────────────────────────
print("Generando leads...")

lead_sources = ["seo", "sem", "direct", "referral", "social", "email"]
lead_source_weights = [0.30, 0.20, 0.15, 0.15, 0.12, 0.08]

# 30% de leads convierten en cita
n_converted = int(N_LEADS * 0.30)
convertible_appts = random.sample(completed_appt_ids, min(n_converted, len(completed_appt_ids)))
appt_set = set(convertible_appts)
appt_idx = 0

leads = []
for i in range(1, N_LEADS + 1):
    country = random.choice(country_ids)
    specialty = random.choice(specialty_ids)
    created = random_ts(date(2021, 6, 1), date(2024, 12, 31))

    # Asignar status y conversión
    if appt_idx < len(convertible_appts) and random.random() < 0.30:
        lead_status = "converted"
        converted_appt_id = convertible_appts[appt_idx]
        appt_idx += 1
        # Paciente del appointment
        appt_row = df_appointments[
            df_appointments["appointment_id"] == converted_appt_id
        ].iloc[0]
        patient_id = appt_row["patient_id"]
        doctor_id = appt_row["doctor_id"]
    else:
        lead_status = random.choices(
            ["new", "contacted", "lost"],
            [0.30, 0.35, 0.35]
        )[0]
        converted_appt_id = None
        patient_id = random.choice(patient_ids) if random.random() > 0.3 else None
        doctor_id = random.choice(doctor_ids) if random.random() > 0.5 else None

    leads.append({
        "lead_id": f"LED{i:06d}",
        "patient_id": patient_id,
        "doctor_id": doctor_id,
        "specialty_id": specialty,
        "country_id": country,
        "created_at": created,
        "lead_source": random.choices(lead_sources, lead_source_weights)[0],
        "lead_status": lead_status,
        "converted_appointment_id": converted_appt_id,
    })

df_leads = pd.DataFrame(leads)
df_leads.to_csv(OUTPUT_DIR / "leads.csv", index=False)
print(f"  → {len(df_leads)} leads")


# ── Resumen ──────────────────────────────────────────────────────────────────
print("\n✓ Datos generados en data/raw/")
print(f"  specialties:  {len(df_specialties):>6}")
print(f"  countries:    {len(df_countries):>6}")
print(f"  doctors:      {len(df_doctors):>6}")
print(f"  patients:     {len(df_patients):>6}")
print(f"  appointments: {len(df_appointments):>6}")
print(f"  payments:     {len(df_payments):>6}")
print(f"  leads:        {len(df_leads):>6}")
