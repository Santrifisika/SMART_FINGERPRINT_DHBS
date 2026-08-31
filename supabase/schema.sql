-- ============================================================================
-- PROYEK: Smart Fingerprint Attendance System (ESP32 DevKit V1 + Supabase)
-- DOKUMEN: Database Schema DDL & Atomic Functions
-- FILE: supabase/schema.sql
-- ============================================================================

-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop existing tables if re-initializing (Order is critical due to Foreign Key constraints)
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS student_audio CASCADE;
DROP TABLE IF EXISTS attendance_events CASCADE;
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS fingerprints CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS students CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS settings CASCADE;

-- ----------------------------------------------------------------------------
-- 1. TABLE: profiles
-- Menampung data pengguna dashboard (Admin & Operator) yang terhubung ke Supabase Auth
-- ----------------------------------------------------------------------------
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('ADMIN', 'OPERATOR')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. TABLE: students
-- Menampung demografi dan status keaktifan siswa
-- ----------------------------------------------------------------------------
CREATE TABLE students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nis TEXT UNIQUE NOT NULL,
    nisn TEXT UNIQUE,
    name TEXT NOT NULL,
    class_name TEXT NOT NULL,
    gender VARCHAR(1) NOT NULL CHECK (gender IN ('L', 'P')),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. TABLE: devices
-- Menampung identitas, kredensial terenkripsi, dan telemetri mesin ESP32
-- ----------------------------------------------------------------------------
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id TEXT UNIQUE NOT NULL,              -- Contoh: "ESP32-ABSEN-001"
    device_name TEXT NOT NULL,                    -- Contoh: "Mesin Gerbang Utama"
    device_code TEXT UNIQUE NOT NULL,            -- Contoh: "GERBANG-001"
    device_secret_hash TEXT NOT NULL,            -- Hash HmacSHA256 Secret Device
    location TEXT,
    status TEXT NOT NULL DEFAULT 'OFFLINE' CHECK (status IN ('ONLINE', 'OFFLINE', 'MAINTENANCE', 'DISABLED')),
    last_seen TIMESTAMPTZ,
    ip_address TEXT,
    wifi_rssi INT2,
    firmware_version TEXT DEFAULT '1.0.0',
    sensor_status TEXT DEFAULT 'OK',
    dfplayer_status TEXT DEFAULT 'OK',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 4. TABLE: fingerprints
-- Relasi antara Fingerprint ID lokal sensor (1-50) dengan Student ID di database
-- ----------------------------------------------------------------------------
CREATE TABLE fingerprints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    fingerprint_id INT2 NOT NULL CHECK (fingerprint_id >= 1 AND fingerprint_id <= 50),
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_fingerprint_per_device UNIQUE (device_id, fingerprint_id)
);

-- ----------------------------------------------------------------------------
-- 5. TABLE: attendance
-- Rekap absensi siswa harian yang sudah tervalidasi
-- ----------------------------------------------------------------------------
CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    fingerprint_id INT2 NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id),
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    scan_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL CHECK (status IN ('PRESENT', 'LATE', 'REJECTED', 'FAILED')),
    attendance_type TEXT NOT NULL DEFAULT 'IN' CHECK (attendance_type IN ('IN', 'OUT')),
    event_id UUID UNIQUE NOT NULL, -- UUID Idempotency Key dari ESP32
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 6. TABLE: attendance_events
-- Raw log setiap event pembacaan sensor/mesin untuk audit & penanganan offline sync
-- ----------------------------------------------------------------------------
CREATE TABLE attendance_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID UNIQUE NOT NULL,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    fingerprint_id INT2 NOT NULL,
    student_id UUID REFERENCES students(id) ON DELETE SET NULL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type TEXT NOT NULL DEFAULT 'ATTENDANCE',
    sync_status TEXT NOT NULL DEFAULT 'REALTIME' CHECK (sync_status IN ('REALTIME', 'OFFLINE_SYNCED')),
    raw_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 7. TABLE: student_audio
-- Pemetaan file audio MP3 pada MicroSD DFPlayer dengan identitas siswa
-- ----------------------------------------------------------------------------
CREATE TABLE student_audio (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,                     -- Contoh: "0001.mp3"
    audio_type TEXT NOT NULL DEFAULT 'STUDENT_NAME',
    version INT2 DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 8. TABLE: settings
-- Konfigurasi global sekolah, jam masuk, jam terlambat, dan timezone
-- ----------------------------------------------------------------------------
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 9. TABLE: audit_logs
-- Rekam jejak seluruh aktivitas perubahan data sensitif oleh Admin/Operator
-- ----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target TEXT NOT NULL,
    target_id UUID,
    description TEXT,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- OPTIMASI INDEX DATABASE
-- Mencegah bottleneck saat query ribuan siswa dan jutaan baris absensi
-- ----------------------------------------------------------------------------
CREATE INDEX idx_students_nis ON students(nis);
CREATE INDEX idx_students_status ON students(status);
CREATE INDEX idx_fingerprints_student ON fingerprints(student_id);
CREATE INDEX idx_fingerprints_lookup ON fingerprints(device_id, fingerprint_id);
CREATE INDEX idx_attendance_student ON attendance(student_id);
CREATE INDEX idx_attendance_date ON attendance(attendance_date);
CREATE INDEX idx_attendance_scan_time ON attendance(scan_time);
CREATE INDEX idx_attendance_device ON attendance(device_id);
CREATE INDEX idx_devices_device_id ON devices(device_id);
CREATE INDEX idx_devices_last_seen ON devices(last_seen);
CREATE INDEX idx_events_event_id ON attendance_events(event_id);

-- ----------------------------------------------------------------------------
-- TRIGGER UNTUK OTOMATISASI UPDATED_AT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_modtime BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_students_modtime BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_devices_modtime BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_fingerprints_modtime BEFORE UPDATE ON fingerprints FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_student_audio_modtime BEFORE UPDATE ON student_audio FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- STORED PROCEDURE ATOMIK: process_device_attendance
-- Menangani validasi device, ekstraksi siswa, pengecekan duplikasi, dan pencatatan absensi
-- secara ATOMIK untuk menghindari Race Condition.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION process_device_attendance(
    p_device_id_str TEXT,
    p_fingerprint_id INT2,
    p_event_id UUID,
    p_scan_time TIMESTAMPTZ DEFAULT NOW(),
    p_sync_status TEXT DEFAULT 'REALTIME'
)
RETURNS JSONB AS $$
DECLARE
    v_device_uuid UUID;
    v_student_id UUID;
    v_student_name TEXT;
    v_class_name TEXT;
    v_audio_file TEXT;
    v_attendance_date DATE;
    v_existing_attendance_id UUID;
    v_existing_event_id UUID;
    v_entry_time TIME;
    v_late_time TIME;
    v_scan_time_only TIME;
    v_calculated_status TEXT;
    v_attendance_id UUID;
BEGIN
    -- 1. Cek Idempotency Event ID (Pencegahan request ganda)
    SELECT event_id INTO v_existing_event_id 
    FROM attendance_events 
    WHERE event_id = p_event_id;

    IF v_existing_event_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', jsonb_build_object(
                'code', 'EVENT_ALREADY_PROCESSED',
                'message', 'Event ID ini sudah pernah diproses sebelumnya'
            )
        );
    END IF;

    -- 2. Validasi Keberadaan Perangkat (Device Check)
    SELECT id INTO v_device_uuid 
    FROM devices 
    WHERE device_id = p_device_id_str AND status = 'ONLINE';

    IF v_device_uuid IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', jsonb_build_object(
                'code', 'DEVICE_UNAUTHORIZED',
                'message', 'Perangkat tidak terdaftar atau tidak aktif'
            )
        );
    END IF;

    -- 3. Cari Siswa berdasarkan Fingerprint ID & Device ID
    SELECT f.student_id, s.name, s.class_name 
    INTO v_student_id, v_student_name, v_class_name
    FROM fingerprints f
    JOIN students s ON f.student_id = s.id
    WHERE (f.device_id = v_device_uuid OR f.device_id IS NULL)
      AND f.fingerprint_id = p_fingerprint_id
      AND f.status = 'ACTIVE'
      AND s.status = 'ACTIVE';

    IF v_student_id IS NULL THEN
        -- Catat Raw Event Unknown Fingerprint
        INSERT INTO attendance_events (event_id, device_id, fingerprint_id, event_time, sync_status, raw_payload)
        VALUES (p_event_id, v_device_uuid, p_fingerprint_id, p_scan_time, p_sync_status, jsonb_build_object('reason', 'UNKNOWN_FINGERPRINT'));

        RETURN jsonb_build_object(
            'success', false,
            'error', jsonb_build_object(
                'code', 'FINGERPRINT_NOT_REGISTERED',
                'message', 'Fingerprint belum terdaftar pada sistem'
            )
        );
    END IF;

    -- 4. Tentukan Tanggal & Jam Scan
    v_attendance_date := (p_scan_time AT TIME ZONE 'Asia/Makassar')::DATE;
    v_scan_time_only := (p_scan_time AT TIME ZONE 'Asia/Makassar')::TIME;

    -- 5. Cek Anti-Duplikasi (Siswa sudah absen masuk pada hari yang sama)
    SELECT id INTO v_existing_attendance_id
    FROM attendance
    WHERE student_id = v_student_id
      AND attendance_date = v_attendance_date
      AND attendance_type = 'IN'
      AND status IN ('PRESENT', 'LATE');

    IF v_existing_attendance_id IS NOT NULL THEN
        -- Catat Event Duplikat
        INSERT INTO attendance_events (event_id, device_id, fingerprint_id, student_id, event_time, sync_status, raw_payload)
        VALUES (p_event_id, v_device_uuid, p_fingerprint_id, v_student_id, p_scan_time, p_sync_status, jsonb_build_object('reason', 'DUPLICATE_ATTENDANCE'));

        RETURN jsonb_build_object(
            'success', false,
            'error', jsonb_build_object(
                'code', 'DUPLICATE_ATTENDANCE',
                'message', 'Siswa sudah melakukan absensi hari ini'
            ),
            'student', jsonb_build_object(
                'id', v_student_id,
                'name', v_student_name,
                'class_name', v_class_name
            )
        );
    END IF;

    -- 6. Ambil Pengaturan Jam Masuk & Batas Terlambat
    SELECT (value->>'entry_time')::TIME, (value->>'late_time')::TIME 
    INTO v_entry_time, v_late_time
    FROM settings
    WHERE key = 'schedule_config';

    IF v_entry_time IS NULL THEN
        v_entry_time := '07:00:00'::TIME;
        v_late_time  := '07:15:00'::TIME;
    END IF;

    -- 7. Logika Penentuan Status Absensi (PRESENT vs LATE)
    IF v_scan_time_only <= v_entry_time THEN
        v_calculated_status := 'PRESENT';
    ELSIF v_scan_time_only <= v_late_time THEN
        v_calculated_status := 'LATE';
    ELSE
        v_calculated_status := 'LATE';
    END IF;

    -- 8. Ambil File Audio MP3 Siswa (jika ada)
    SELECT file_name INTO v_audio_file
    FROM student_audio
    WHERE student_id = v_student_id AND status = 'ACTIVE'
    LIMIT 1;

    IF v_audio_file IS NULL THEN
        -- Format default nama file berdasarkan ID fingerprint (e.g. 1 -> "0001.mp3")
        v_audio_file := LPAD(p_fingerprint_id::TEXT, 4, '0') || '.mp3';
    END IF;

    -- 9. Insert Record Absensi Utama
    INSERT INTO attendance (
        student_id, fingerprint_id, device_id, attendance_date, scan_time, status, attendance_type, event_id
    ) VALUES (
        v_student_id, p_fingerprint_id, v_device_uuid, v_attendance_date, p_scan_time, v_calculated_status, 'IN', p_event_id
    ) RETURNING id INTO v_attendance_id;

    -- 10. Insert Record Attendance Events Log
    INSERT INTO attendance_events (
        event_id, device_id, fingerprint_id, student_id, event_time, sync_status, raw_payload
    ) VALUES (
        p_event_id, v_device_uuid, p_fingerprint_id, v_student_id, p_scan_time, p_sync_status, jsonb_build_object('attendance_id', v_attendance_id, 'status', v_calculated_status)
    );

    -- 11. Kembalikan Response JSON Sukses
    RETURN jsonb_build_object(
        'success', true,
        'student', jsonb_build_object(
            'id', v_student_id,
            'name', v_student_name,
            'class_name', v_class_name
        ),
        'attendance', jsonb_build_object(
            'id', v_attendance_id,
            'status', v_calculated_status,
            'type', 'IN',
            'scan_time', to_char(v_scan_time_only, 'HH24:MI:SS'),
            'attendance_date', v_attendance_date
        ),
        'audio', jsonb_build_object(
            'file', v_audio_file
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- SEED DATA CONFIGURATION
-- ----------------------------------------------------------------------------
INSERT INTO settings (key, value, description) VALUES
('school_info', '{"school_name": "SMA Negeri 1 Technology", "timezone": "Asia/Makassar"}', 'Informasi Umum Sekolah'),
('schedule_config', '{"entry_time": "07:00:00", "late_time": "07:15:00", "exit_time": "15:00:00"}', 'Jadwal Jam Masuk & Pulang'),
('device_config', '{"heartbeat_interval": 30, "duplicate_timeout": 300}', 'Konfigurasi Parameter Mesin ESP32');

-- Seed Data Contoh Perangkat ESP32 (Secret: "super_secret_device_key_123")
INSERT INTO devices (device_id, device_name, device_code, device_secret_hash, location, status, ip_address, wifi_rssi) VALUES
('ESP32-ABSEN-001', 'Mesin Absensi Gerbang Utama', 'GERBANG-001', crypt('super_secret_device_key_123', gen_salt('bf')), 'Gerbang Depan', 'ONLINE', '192.168.1.100', -55);
