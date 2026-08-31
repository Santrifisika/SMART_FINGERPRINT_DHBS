-- ============================================================================
-- PROYEK: Smart Fingerprint Attendance System (ESP32 DevKit V1 + Supabase)
-- DOKUMEN: Row Level Security (RLS) Policies
-- FILE: supabase/policies.sql
-- ============================================================================

-- Aktifkan Row Level Security (RLS) pada seluruh tabel sensitif
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_audio ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS UNTUK VERIFIKASI ROLE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'ADMIN'
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_operator_or_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role IN ('ADMIN', 'OPERATOR')
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- POLICIES: profiles
-- Admin memegang Hak Penuh (FULL ACCESS). Operator hanya membaca profil sendiri.
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to profiles"
    ON profiles FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

-- ----------------------------------------------------------------------------
-- POLICIES: students
-- Admin: CRUD penuh. Operator: READ (Melihat data siswa).
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to students"
    ON students FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view students"
    ON students FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: devices
-- Admin: Pengelolaan penuh device. Operator: Hanya melihat status device.
-- Service Role (Edge Functions): Memperbarui status heartbeat & telemetri.
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to devices"
    ON devices FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view devices"
    ON devices FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: fingerprints
-- Admin & Operator: Dapat membaca dan menambahkan pendaftaran fingerprint (Enrollment).
-- Operator TIDAK boleh menghapus database fingerprint (Delete hanya Admin).
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to fingerprints"
    ON fingerprints FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view fingerprints"
    ON fingerprints FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

CREATE POLICY "Operators can insert fingerprints during enrollment"
    ON fingerprints FOR INSERT
    TO authenticated
    WITH CHECK (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: attendance
-- Admin & Operator: Dapat melihat riwayat absensi.
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to attendance"
    ON attendance FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view attendance"
    ON attendance FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: attendance_events
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to attendance_events"
    ON attendance_events FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view attendance_events"
    ON attendance_events FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: student_audio
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins have full access to student_audio"
    ON student_audio FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view student_audio"
    ON student_audio FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: settings
-- Admin: Mengubah jam masuk / nama sekolah. Operator: hanya membaca settings.
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins can manage settings"
    ON settings FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "Operators can view settings"
    ON settings FOR SELECT
    TO authenticated
    USING (is_operator_or_admin());

-- ----------------------------------------------------------------------------
-- POLICIES: audit_logs
-- Hanya Admin yang dapat membaca log audit. Tidak ada role yang bisa menghapus log.
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins can view audit_logs"
    ON audit_logs FOR SELECT
    TO authenticated
    USING (is_admin());

CREATE POLICY "Authenticated users can insert audit_logs"
    ON audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (is_operator_or_admin());
