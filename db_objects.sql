-- ============================================================
--  Hospital & Clinic Management System
--  DB Objects: Roles, Views, Functions, Triggers
--  Run this AFTER schema.sql
-- ============================================================


-- ============================================================
-- PART 1 — ROLES & AUTHORIZATION
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_admin') THEN
        CREATE ROLE role_admin;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_doctor') THEN
        CREATE ROLE role_doctor;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_nurse') THEN
        CREATE ROLE role_nurse;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_billing_staff') THEN
        CREATE ROLE role_billing_staff;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_patient') THEN
        CREATE ROLE role_patient;
    END IF;
END;
$$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO role_admin, role_doctor, role_nurse, role_billing_staff, role_patient;

-- Admin: full access to everything
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_doctor, role_nurse, role_billing_staff;

-- Doctor: read patients/rooms/departments, manage appointments, records, prescriptions
GRANT SELECT ON Patient, Department, Room, Doctor, Nurse TO role_doctor;
GRANT SELECT, INSERT, UPDATE ON Appointment TO role_doctor;
GRANT SELECT, INSERT, UPDATE ON MedicalRecord TO role_doctor;
GRANT SELECT, INSERT ON Prescription TO role_doctor;
GRANT SELECT ON Billing TO role_doctor;

-- Nurse: read patients/doctors, manage appointments and room assignments
GRANT SELECT ON Patient, Doctor, Department TO role_nurse;
GRANT SELECT, INSERT, UPDATE ON Appointment TO role_nurse;
GRANT SELECT, INSERT, UPDATE ON RoomAssignment TO role_nurse;
GRANT SELECT, UPDATE ON Room TO role_nurse;

-- Billing staff: billing + read patient names + read appointments
GRANT SELECT, INSERT, UPDATE ON Billing TO role_billing_staff;
GRANT SELECT ON Patient TO role_billing_staff;
GRANT SELECT ON Appointment TO role_billing_staff;

-- Patient: read-only on their own data (app enforces row-level filtering)
GRANT SELECT ON Appointment TO role_patient;
GRANT SELECT ON MedicalRecord TO role_patient;
GRANT SELECT ON Prescription TO role_patient;
GRANT SELECT ON Billing TO role_patient;
GRANT SELECT ON Doctor, Department TO role_patient;
GRANT SELECT ON Person TO role_admin, role_doctor, role_nurse, role_billing_staff;


-- ============================================================
-- PART 2 — VIEWS
-- ============================================================

-- 1. Full appointment schedule — used by doctors, nurses, admin
CREATE OR REPLACE VIEW view_doctor_schedule AS
SELECT
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    a.status,
    a.notes,
    p.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    p.phone  AS patient_phone,
    p.blood_type,
    d.doctor_id,
    d.first_name || ' ' || d.last_name AS doctor_name,
    d.specialty,
    dept.name AS department_name
FROM Appointment a
JOIN Patient  p    ON a.patient_id   = p.patient_id
JOIN Doctor   d    ON a.doctor_id    = d.doctor_id
LEFT JOIN Department dept ON d.department_id = dept.department_id;

GRANT SELECT ON view_doctor_schedule TO role_doctor, role_nurse, role_admin;

-- -------------------------------------------------------
-- 1b. Person inheritance/specialization view
CREATE OR REPLACE VIEW view_person_specialization AS
SELECT
    p.person_id,
    p.person_type,
    p.first_name,
    p.last_name,
    p.phone,
    p.email,
    d.doctor_id,
    n.nurse_id,
    pat.patient_id,
    s.staff_id,
    CASE
        WHEN d.doctor_id IS NOT NULL THEN 'Doctor subtype'
        WHEN n.nurse_id IS NOT NULL THEN 'Nurse subtype'
        WHEN pat.patient_id IS NOT NULL THEN 'Patient subtype'
        WHEN s.staff_id IS NOT NULL THEN 'Staff subtype'
        ELSE 'Unlinked supertype row'
    END AS subtype_status
FROM Person p
LEFT JOIN Doctor d ON p.person_id = d.person_id
LEFT JOIN Nurse n ON p.person_id = n.person_id
LEFT JOIN Patient pat ON p.person_id = pat.person_id
LEFT JOIN Staff s ON p.person_id = s.person_id;

GRANT SELECT ON view_person_specialization TO role_admin, role_doctor, role_nurse, role_billing_staff;

-- -------------------------------------------------------
-- 2. Patient summary — aggregated stats per patient.
-- Child tables are aggregated separately to avoid join multiplication
-- when a patient has multiple appointments, records, and bills.
CREATE OR REPLACE VIEW view_patient_summary AS
WITH appointment_counts AS (
    SELECT patient_id, COUNT(*) AS total_appointments
    FROM Appointment
    GROUP BY patient_id
),
record_counts AS (
    SELECT patient_id, COUNT(*) AS total_records
    FROM MedicalRecord
    GROUP BY patient_id
),
billing_totals AS (
    SELECT
        patient_id,
        COALESCE(SUM(amount), 0) AS total_billed,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN amount ELSE 0 END), 0) AS total_paid
    FROM Billing
    GROUP BY patient_id
)
SELECT
    p.patient_id,
    p.first_name,
    p.last_name,
    p.first_name || ' ' || p.last_name          AS full_name,
    p.date_of_birth,
    p.gender,
    p.blood_type,
    p.phone,
    p.email,
    p.registered_at,
    COALESCE(ac.total_appointments, 0)            AS total_appointments,
    COALESCE(rc.total_records, 0)                 AS total_records,
    COALESCE(bt.total_billed, 0)                  AS total_billed,
    COALESCE(bt.total_paid, 0)                    AS total_paid
FROM Patient p
LEFT JOIN appointment_counts ac ON p.patient_id = ac.patient_id
LEFT JOIN record_counts      rc ON p.patient_id = rc.patient_id
LEFT JOIN billing_totals     bt ON p.patient_id = bt.patient_id;

GRANT SELECT ON view_patient_summary TO role_admin, role_doctor, role_nurse;

-- -------------------------------------------------------
-- 3. Billing summary — enriched billing rows for billing staff
CREATE OR REPLACE VIEW view_billing_summary AS
SELECT
    b.billing_id,
    b.billing_date,
    b.payment_date,
    b.amount,
    b.payment_status,
    b.description,
    p.patient_id,
    p.first_name || ' ' || p.last_name   AS patient_name,
    p.phone                               AS patient_phone,
    a.appointment_date,
    d.first_name || ' ' || d.last_name   AS doctor_name
FROM Billing b
JOIN  Patient     p ON b.patient_id    = p.patient_id
LEFT JOIN Appointment  a ON b.appointment_id = a.appointment_id
LEFT JOIN Doctor       d ON a.doctor_id      = d.doctor_id;

GRANT SELECT ON view_billing_summary TO role_billing_staff, role_admin;

-- -------------------------------------------------------
-- 4. Room availability — shows current occupant if any
CREATE OR REPLACE VIEW view_room_availability AS
SELECT
    r.room_id,
    r.room_number,
    r.room_type,
    r.capacity,
    r.is_available,
    dept.name                             AS department_name,
    ra.assignment_id,
    ra.patient_id                         AS current_patient_id,
    p.first_name || ' ' || p.last_name   AS current_patient_name,
    ra.check_in_date
FROM Room r
LEFT JOIN Department    dept ON r.department_id   = dept.department_id
LEFT JOIN RoomAssignment ra  ON r.room_id         = ra.room_id AND ra.is_active = TRUE
LEFT JOIN Patient        p   ON ra.patient_id     = p.patient_id;

GRANT SELECT ON view_room_availability TO role_admin, role_nurse, role_doctor;

-- -------------------------------------------------------
-- 5. Department statistics — aggregate counts per department
CREATE OR REPLACE VIEW view_department_stats AS
SELECT
    dept.department_id,
    dept.name                                                    AS department_name,
    dept.location,
    COUNT(DISTINCT d.doctor_id)                                  AS doctor_count,
    COUNT(DISTINCT n.nurse_id)                                   AS nurse_count,
    COUNT(DISTINCT r.room_id)                                    AS room_count,
    COUNT(DISTINCT CASE WHEN r.is_available = FALSE
                        THEN r.room_id END)                      AS occupied_rooms,
    COUNT(DISTINCT a.appointment_id)                             AS total_appointments
FROM Department dept
LEFT JOIN Doctor       d  ON dept.department_id = d.department_id
LEFT JOIN Nurse        n  ON dept.department_id = n.department_id
LEFT JOIN Room         r  ON dept.department_id = r.department_id
LEFT JOIN Appointment  a  ON d.doctor_id        = a.doctor_id
GROUP BY dept.department_id, dept.name, dept.location;

GRANT SELECT ON view_department_stats TO role_admin, role_doctor, role_nurse;

-- -------------------------------------------------------
-- 6. RIGHT OUTER JOIN report — keeps every doctor, even with no appointments
CREATE OR REPLACE VIEW view_doctor_appointment_right_report AS
SELECT
    d.doctor_id,
    d.first_name || ' ' || d.last_name AS doctor_name,
    d.specialty,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    a.status,
    p.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name
FROM Appointment a
RIGHT OUTER JOIN Doctor d ON a.doctor_id = d.doctor_id
LEFT JOIN Patient p ON a.patient_id = p.patient_id;

GRANT SELECT ON view_doctor_appointment_right_report TO role_admin, role_doctor, role_nurse, role_billing_staff;

-- -------------------------------------------------------
-- 7. FULL OUTER JOIN report — reconciles appointments with billing rows
-- All three branches are genuinely reachable:
--   appointment_with_bill      : most completed appointments (normal case)
--   appointment_without_bill   : scheduled/cancelled appointments not yet billed
--   bill_without_appointment   : Billing.appointment_id SET NULL (appointment deleted)
--                                or a billing row created without a linked appointment
CREATE OR REPLACE VIEW view_patient_billing_full_report AS
SELECT
    a.appointment_id,
    a.appointment_date,
    a.status                                              AS appointment_status,
    COALESCE(pa.first_name || ' ' || pa.last_name, '—')  AS patient_name,
    b.billing_id,
    b.amount,
    b.payment_status,
    b.billing_date,
    CASE
        WHEN a.appointment_id IS NOT NULL AND b.billing_id IS NOT NULL
            THEN 'appointment_with_bill'
        WHEN a.appointment_id IS NOT NULL AND b.billing_id IS NULL
            THEN 'appointment_without_bill'
        ELSE 'bill_without_appointment'
    END AS report_status
FROM Appointment a
FULL OUTER JOIN Billing b ON a.appointment_id = b.appointment_id
LEFT JOIN Patient pa ON COALESCE(a.patient_id, b.patient_id) = pa.patient_id;

GRANT SELECT ON view_patient_billing_full_report TO role_admin, role_billing_staff;


-- ============================================================
-- PART 3 — FUNCTIONS
-- ============================================================

-- 1. Total billed amount for a patient (all bills)
CREATE OR REPLACE FUNCTION calculate_patient_bill(p_id INT)
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO total
    FROM Billing
    WHERE patient_id = p_id;
    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------
-- 2. Outstanding (unpaid) amount for a patient
CREATE OR REPLACE FUNCTION calculate_outstanding_bill(p_id INT)
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO total
    FROM Billing
    WHERE patient_id = p_id AND payment_status != 'paid';
    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------
-- 3. Check if a doctor has a free slot (returns TRUE = available)
CREATE OR REPLACE FUNCTION check_doctor_availability(d_id INT, appt_date DATE, appt_time TIME)
RETURNS BOOLEAN AS $$
DECLARE
    conflict INT;
BEGIN
    SELECT COUNT(*) INTO conflict
    FROM Appointment
    WHERE doctor_id        = d_id
      AND appointment_date = appt_date
      AND appointment_time = appt_time
      AND status          != 'cancelled';
    RETURN conflict = 0;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------
-- 4. Count distinct patients seen by a doctor
CREATE OR REPLACE FUNCTION count_doctor_patients(d_id INT)
RETURNS INT AS $$
DECLARE
    cnt INT;
BEGIN
    SELECT COUNT(DISTINCT patient_id) INTO cnt
    FROM Appointment
    WHERE doctor_id = d_id AND status != 'cancelled';
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------
-- 5. Get patient age from date of birth
CREATE OR REPLACE FUNCTION get_patient_age(p_id INT)
RETURNS INT AS $$
DECLARE
    dob DATE;
BEGIN
    SELECT date_of_birth INTO dob FROM Patient WHERE patient_id = p_id;
    IF dob IS NULL THEN RETURN NULL; END IF;
    RETURN DATE_PART('year', AGE(dob))::INT;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------
-- 6. TABLE FUNCTION — full appointment history for a patient
--    Returns one row per appointment, with diagnosis and billing joined in.
--    Called as: SELECT * FROM get_patient_appointments_full(patient_id)
CREATE OR REPLACE FUNCTION get_patient_appointments_full(p_id INT)
RETURNS TABLE(
    appointment_id   INT,
    appointment_date DATE,
    appointment_time TIME,
    status           VARCHAR,
    doctor_name      TEXT,
    specialty        VARCHAR,
    department_name  VARCHAR,
    diagnosis        TEXT,
    medications      TEXT,
    billed_amount    NUMERIC,
    payment_status   VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.appointment_id,
        a.appointment_date,
        a.appointment_time,
        a.status,
        (d.first_name || ' ' || d.last_name)::TEXT         AS doctor_name,
        d.specialty,
        COALESCE(dept.name, '—')::VARCHAR                   AS department_name,
        COALESCE(mr.diagnosis, '—')::TEXT                   AS diagnosis,
        COALESCE(
            STRING_AGG(DISTINCT pr.medication_name, ', '), '—'
        )::TEXT                                             AS medications,
        COALESCE(b.amount, 0)                               AS billed_amount,
        COALESCE(b.payment_status, '—')::VARCHAR            AS payment_status
    FROM Appointment a
    JOIN  Doctor       d    ON a.doctor_id      = d.doctor_id
    LEFT JOIN Department   dept ON d.department_id  = dept.department_id
    LEFT JOIN MedicalRecord mr  ON mr.appointment_id = a.appointment_id
    LEFT JOIN Prescription  pr  ON pr.record_id      = mr.record_id
    LEFT JOIN Billing       b   ON b.appointment_id  = a.appointment_id
    WHERE a.patient_id = p_id
    GROUP BY a.appointment_id, a.appointment_date, a.appointment_time,
             a.status, d.first_name, d.last_name, d.specialty,
             dept.name, mr.diagnosis, b.amount, b.payment_status
    ORDER BY a.appointment_date DESC, a.appointment_time DESC;
END;
$$ LANGUAGE plpgsql;

-- Grant function execution
GRANT EXECUTE ON FUNCTION calculate_patient_bill(INT)       TO role_admin, role_billing_staff, role_doctor;
GRANT EXECUTE ON FUNCTION calculate_outstanding_bill(INT)   TO role_admin, role_billing_staff, role_doctor;
GRANT EXECUTE ON FUNCTION check_doctor_availability(INT, DATE, TIME) TO role_admin, role_doctor, role_nurse;
GRANT EXECUTE ON FUNCTION count_doctor_patients(INT)        TO role_admin, role_doctor;
GRANT EXECUTE ON FUNCTION get_patient_age(INT)              TO role_admin, role_doctor, role_nurse;
GRANT EXECUTE ON FUNCTION get_patient_appointments_full(INT) TO role_admin, role_doctor, role_nurse, role_patient;

-- Local Flask connection user from .env. This gives the application login
-- the admin role while preserving the project role structure.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hospital_admin') THEN
        GRANT role_admin TO hospital_admin;
    END IF;
END;
$$;


-- ============================================================
-- PART 4 — AUDIT LOG TABLE + TRIGGERS
-- ============================================================

CREATE TABLE IF NOT EXISTS AuditLog (
    log_id      SERIAL PRIMARY KEY,
    table_name  VARCHAR(50)  NOT NULL,
    action      VARCHAR(10)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    record_id   INT,
    changed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details     TEXT
);

GRANT SELECT ON AuditLog TO role_admin;

-- -------------------------------------------------------
-- Trigger 1: Room check-in → mark room unavailable
CREATE OR REPLACE FUNCTION fn_room_checkin()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Room SET is_available = FALSE WHERE room_id = NEW.room_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_room_checkin ON RoomAssignment;
CREATE TRIGGER trg_room_checkin
AFTER INSERT ON RoomAssignment
FOR EACH ROW
WHEN (NEW.is_active = TRUE)
EXECUTE FUNCTION fn_room_checkin();

-- -------------------------------------------------------
-- Trigger 2: Room check-out → mark room available again
CREATE OR REPLACE FUNCTION fn_room_checkout()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
        UPDATE Room SET is_available = TRUE WHERE room_id = NEW.room_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_room_checkout ON RoomAssignment;
CREATE TRIGGER trg_room_checkout
AFTER UPDATE ON RoomAssignment
FOR EACH ROW
EXECUTE FUNCTION fn_room_checkout();

-- -------------------------------------------------------
-- Trigger 3: Appointment completed → auto-create a blank billing record
CREATE OR REPLACE FUNCTION fn_auto_billing()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        IF NOT EXISTS (
            SELECT 1 FROM Billing WHERE appointment_id = NEW.appointment_id
        ) THEN
            INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, description)
            VALUES (NEW.patient_id, NEW.appointment_id, 0, 'unpaid',
                    'Auto-generated on appointment completion');
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_billing ON Appointment;
CREATE TRIGGER trg_auto_billing
AFTER UPDATE ON Appointment
FOR EACH ROW
EXECUTE FUNCTION fn_auto_billing();

-- -------------------------------------------------------
-- Trigger 4: Audit log on MedicalRecord insert/update
CREATE OR REPLACE FUNCTION fn_audit_medical_record()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO AuditLog (table_name, action, record_id, details)
        VALUES ('MedicalRecord', 'INSERT', NEW.record_id,
                'Patient #' || NEW.patient_id || ' — Diagnosis: ' || NEW.diagnosis);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO AuditLog (table_name, action, record_id, details)
        VALUES ('MedicalRecord', 'UPDATE', NEW.record_id,
                'Diagnosis changed from "' || OLD.diagnosis || '" to "' || NEW.diagnosis || '"');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_medical_record ON MedicalRecord;
CREATE TRIGGER trg_audit_medical_record
AFTER INSERT OR UPDATE ON MedicalRecord
FOR EACH ROW
EXECUTE FUNCTION fn_audit_medical_record();

-- -------------------------------------------------------
-- Trigger 5: Prevent booking a doctor who is not available
CREATE OR REPLACE FUNCTION fn_check_appointment_conflict()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT check_doctor_availability(NEW.doctor_id, NEW.appointment_date, NEW.appointment_time) THEN
        RAISE EXCEPTION 'Doctor is already booked at % on %', NEW.appointment_time, NEW.appointment_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_appointment_conflict ON Appointment;
CREATE TRIGGER trg_appointment_conflict
BEFORE INSERT ON Appointment
FOR EACH ROW
EXECUTE FUNCTION fn_check_appointment_conflict();
