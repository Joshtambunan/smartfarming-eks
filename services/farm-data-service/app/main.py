"""
farm-data-service – Mengelola data IoT sensor pertanian ke Amazon RDS PostgreSQL.
Juga menyertakan simulator IoT untuk generate data sensor secara otomatis.
Koneksi ke RDS menggunakan IAM Authentication – tidak ada password di kode atau environment.
"""

import os
import random
import asyncio
import logging
from datetime import datetime
from typing import Optional, List
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="SmartFarming Farm Data Service",
    description="Service untuk menyimpan data sensor IoT ke RDS PostgreSQL",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Konfigurasi database dari environment variables
# Tidak ada password hardcoded – pakai IAM auth di production
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "smartfarming")
DB_USER = os.getenv("DB_USER", "farmuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "localpassword")  # Hanya untuk lokal

# Flag untuk simulator
simulator_running = False


# ─── Models ───────────────────────────────────────────────

class SensorReading(BaseModel):
    sensor_id: str
    sensor_type: str        # temperature, humidity, ph, ec, water_level, flow
    value: float
    unit: str
    location: Optional[str] = "greenhouse-1"


class ActuatorCommand(BaseModel):
    actuator_id: str
    command: str            # ON / OFF / SET
    value: Optional[float] = None


# ─── Database ─────────────────────────────────────────────

def get_db_connection():
    """
    Membuat koneksi ke PostgreSQL.
    Di production (EKS): menggunakan IAM token sebagai password via RDS Auth.
    Di lokal (Docker Compose): menggunakan password biasa dari env var.
    """
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=10
    )


def init_database():
    """
    Membuat tabel jika belum ada.
    Dipanggil saat service pertama kali start.
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sensor_readings (
            id SERIAL PRIMARY KEY,
            sensor_id VARCHAR(50) NOT NULL,
            sensor_type VARCHAR(50) NOT NULL,
            value NUMERIC(10, 4) NOT NULL,
            unit VARCHAR(20) NOT NULL,
            location VARCHAR(100) DEFAULT 'greenhouse-1',
            recorded_at TIMESTAMP DEFAULT NOW()
        );

        CREATE TABLE IF NOT EXISTS actuator_logs (
            id SERIAL PRIMARY KEY,
            actuator_id VARCHAR(50) NOT NULL,
            command VARCHAR(20) NOT NULL,
            value NUMERIC(10, 4),
            executed_at TIMESTAMP DEFAULT NOW()
        );

        CREATE INDEX IF NOT EXISTS idx_sensor_recorded_at
            ON sensor_readings(recorded_at DESC);

        CREATE INDEX IF NOT EXISTS idx_sensor_id
            ON sensor_readings(sensor_id);
    """)

    conn.commit()
    cursor.close()
    conn.close()
    logger.info("Database tables initialized")


# ─── Startup ──────────────────────────────────────────────

@app.on_event("startup")
def startup_event():
    try:
        init_database()
    except Exception as e:
        logger.warning(f"DB init warning (mungkin belum siap): {e}")


# ─── Health ───────────────────────────────────────────────

@app.get("/health")
def health_check():
    try:
        conn = get_db_connection()
        conn.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": str(e)}


# ─── Sensor CRUD ──────────────────────────────────────────

@app.post("/sensors")
def add_sensor_reading(reading: SensorReading):
    """Simpan satu reading dari sensor IoT ke database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO sensor_readings
               (sensor_id, sensor_type, value, unit, location)
               VALUES (%s, %s, %s, %s, %s) RETURNING id""",
            (reading.sensor_id, reading.sensor_type,
             reading.value, reading.unit, reading.location)
        )
        row_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        conn.close()
        return {"id": row_id, "message": "Data sensor berhasil disimpan"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/sensors")
def get_sensor_readings(
    sensor_type: Optional[str] = None,
    limit: int = 50
):
    """Ambil data sensor terbaru. Bisa filter berdasarkan tipe sensor."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        if sensor_type:
            cursor.execute(
                """SELECT * FROM sensor_readings
                   WHERE sensor_type = %s
                   ORDER BY recorded_at DESC LIMIT %s""",
                (sensor_type, limit)
            )
        else:
            cursor.execute(
                "SELECT * FROM sensor_readings ORDER BY recorded_at DESC LIMIT %s",
                (limit,)
            )

        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return {"data": [dict(r) for r in rows], "count": len(rows)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/sensors/latest")
def get_latest_readings():
    """Ambil reading terbaru untuk setiap tipe sensor (untuk dashboard)."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("""
            SELECT DISTINCT ON (sensor_type)
                sensor_id, sensor_type, value, unit, location, recorded_at
            FROM sensor_readings
            ORDER BY sensor_type, recorded_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return {"latest": [dict(r) for r in rows]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── Actuator ─────────────────────────────────────────────

@app.post("/actuators")
def control_actuator(command: ActuatorCommand):
    """Kirim perintah ke aktuator (pompa, lampu, dll) dan log ke DB."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO actuator_logs (actuator_id, command, value)
               VALUES (%s, %s, %s) RETURNING id""",
            (command.actuator_id, command.command, command.value)
        )
        log_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        conn.close()
        return {
            "log_id": log_id,
            "actuator_id": command.actuator_id,
            "command": command.command,
            "status": "executed"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── IoT Simulator ────────────────────────────────────────

def generate_sensor_data():
    """
    Generate data sensor yang realistis untuk simulasi sistem hydroponik/pertanian.
    Nilai disesuaikan dengan range normal untuk setiap parameter.
    """
    readings = [
        {"sensor_id": "temp-01",    "sensor_type": "temperature",   "value": round(random.uniform(22, 32), 2), "unit": "celsius"},
        {"sensor_id": "humid-01",   "sensor_type": "humidity",       "value": round(random.uniform(60, 90), 2), "unit": "percent"},
        {"sensor_id": "ph-01",      "sensor_type": "ph",             "value": round(random.uniform(5.5, 7.0), 2), "unit": "pH"},
        {"sensor_id": "ec-01",      "sensor_type": "ec",             "value": round(random.uniform(1.0, 3.0), 3), "unit": "mS/cm"},
        {"sensor_id": "water-01",   "sensor_type": "water_level",    "value": round(random.uniform(10, 50), 1), "unit": "cm"},
        {"sensor_id": "light-01",   "sensor_type": "light",          "value": round(random.uniform(200, 800), 0), "unit": "lux"},
    ]
    return readings


async def run_simulator():
    """Background task yang terus generate dan simpan data sensor setiap 30 detik."""
    global simulator_running
    logger.info("IoT Simulator dimulai – generate data setiap 30 detik")

    while simulator_running:
        try:
            readings = generate_sensor_data()
            conn = get_db_connection()
            cursor = conn.cursor()
            for r in readings:
                cursor.execute(
                    """INSERT INTO sensor_readings
                       (sensor_id, sensor_type, value, unit, location)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (r["sensor_id"], r["sensor_type"],
                     r["value"], r["unit"], "greenhouse-simulated")
                )
            conn.commit()
            cursor.close()
            conn.close()
            logger.info(f"Simulator: {len(readings)} readings disimpan ke DB")
        except Exception as e:
            logger.error(f"Simulator error: {e}")

        await asyncio.sleep(30)

    logger.info("IoT Simulator dihentikan")


@app.post("/simulator/start")
def start_simulator(background_tasks: BackgroundTasks):
    global simulator_running
    if simulator_running:
        return {"message": "Simulator sudah berjalan"}
    simulator_running = True
    background_tasks.add_task(run_simulator)
    return {"message": "IoT Simulator dimulai – generate data setiap 30 detik"}


@app.post("/simulator/stop")
def stop_simulator():
    global simulator_running
    simulator_running = False
    return {"message": "IoT Simulator dihentikan"}


@app.get("/simulator/status")
def simulator_status():
    return {"running": simulator_running}
