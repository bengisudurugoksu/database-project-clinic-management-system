-- ============================================================
-- Mock data for Hospital & Clinic Management System
-- Run after schema.sql and db_objects.sql.
-- Demo passwords for seeded non-admin users: demo123
-- ============================================================

-- ------------------------------------------------------------
-- Person supertype rows for inheritance/specialization demo
-- ------------------------------------------------------------
INSERT INTO Person (first_name, last_name, phone, email, person_type)
VALUES
    ('Aylin', 'Demir', '555-1001', 'aylin.demir@hospital.test', 'doctor'),
    ('Mert', 'Kaya', '555-1002', 'mert.kaya@hospital.test', 'doctor'),
    ('Selin', 'Arslan', '555-1003', 'selin.arslan@hospital.test', 'nurse'),
    ('Duru', 'Yilmaz', '555-1004', 'duru.yilmaz@hospital.test', 'patient'),
    ('Kerem', 'Acar', '555-1005', 'kerem.acar@hospital.test', 'patient'),
    ('Buse', 'Celik', '555-1006', 'buse.celik@hospital.test', 'staff')
ON CONFLICT (email) DO NOTHING;

-- ------------------------------------------------------------
-- Departments
-- ------------------------------------------------------------
INSERT INTO Department (name, location, phone)
VALUES
    ('Cardiology', 'Block A - Floor 2', '0216-100-2001'),
    ('Neurology', 'Block B - Floor 3', '0216-100-2002'),
    ('Emergency', 'Block E - Ground', '0216-100-2003')
ON CONFLICT (name) DO NOTHING;

-- ------------------------------------------------------------
-- Doctors
-- ------------------------------------------------------------
INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, 'Cardiologist', p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'aylin.demir@hospital.test'
  AND d.name = 'Cardiology'
ON CONFLICT (email) DO NOTHING;

INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, 'Neurologist', p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'mert.kaya@hospital.test'
  AND d.name = 'Neurology'
ON CONFLICT (email) DO NOTHING;

UPDATE Department
SET head_doctor_id = (
    SELECT doctor_id FROM Doctor WHERE email = 'aylin.demir@hospital.test'
)
WHERE name = 'Cardiology';

-- ------------------------------------------------------------
-- Nurses and staff
-- ------------------------------------------------------------
INSERT INTO Nurse (person_id, first_name, last_name, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'selin.arslan@hospital.test'
  AND d.name = 'Emergency'
ON CONFLICT (email) DO NOTHING;

INSERT INTO Staff (person_id, first_name, last_name, role, phone, email)
SELECT p.person_id, p.first_name, p.last_name, 'admin', p.phone, p.email
FROM Person p
WHERE p.email = 'buse.celik@hospital.test'
ON CONFLICT (email) DO NOTHING;

-- ------------------------------------------------------------
-- Patients
-- ------------------------------------------------------------
INSERT INTO Patient (
    person_id, first_name, last_name, date_of_birth, gender, blood_type,
    phone, email, address, emergency_contact_name, emergency_contact_phone
)
SELECT
    person_id, first_name, last_name, DATE '1998-04-12', 'F', 'A+',
    phone, email, 'Kadikoy, Istanbul', 'Ece Yilmaz', '555-2001'
FROM Person
WHERE email = 'duru.yilmaz@hospital.test'
ON CONFLICT (person_id) DO NOTHING;

INSERT INTO Patient (
    person_id, first_name, last_name, date_of_birth, gender, blood_type,
    phone, email, address, emergency_contact_name, emergency_contact_phone
)
SELECT
    person_id, first_name, last_name, DATE '1986-09-20', 'M', 'O-',
    phone, email, 'Besiktas, Istanbul', 'Deniz Acar', '555-2002'
FROM Person
WHERE email = 'kerem.acar@hospital.test'
ON CONFLICT (person_id) DO NOTHING;

-- ------------------------------------------------------------
-- Rooms
-- ------------------------------------------------------------
INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'A201', 'General', 2, TRUE, department_id FROM Department WHERE name = 'Cardiology'
ON CONFLICT (room_number) DO NOTHING;

INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'E101', 'Emergency', 1, TRUE, department_id FROM Department WHERE name = 'Emergency'
ON CONFLICT (room_number) DO NOTHING;

INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'B301', 'ICU', 1, TRUE, department_id FROM Department WHERE name = 'Neurology'
ON CONFLICT (room_number) DO NOTHING;

-- ------------------------------------------------------------
-- Appointments
-- ------------------------------------------------------------
INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id, CURRENT_DATE, TIME '09:00', 'scheduled', 'Routine cardiology check'
FROM Patient p, Doctor d
WHERE p.email = 'duru.yilmaz@hospital.test'
  AND d.email = 'aylin.demir@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.doctor_id = d.doctor_id
        AND a.appointment_date = CURRENT_DATE
        AND a.appointment_time = TIME '09:00'
  );

INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id, CURRENT_DATE + 1, TIME '14:30', 'completed', 'Neurology consultation'
FROM Patient p, Doctor d
WHERE p.email = 'kerem.acar@hospital.test'
  AND d.email = 'mert.kaya@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.doctor_id = d.doctor_id
        AND a.appointment_date = CURRENT_DATE + 1
        AND a.appointment_time = TIME '14:30'
  );

-- ------------------------------------------------------------
-- Medical records and weak entity prescriptions
-- ------------------------------------------------------------
INSERT INTO MedicalRecord (patient_id, doctor_id, appointment_id, diagnosis, notes)
SELECT p.patient_id, d.doctor_id, a.appointment_id, 'Migraine evaluation', 'Patient advised to track symptoms.'
FROM Patient p
JOIN Appointment a ON a.patient_id = p.patient_id
JOIN Doctor d ON d.doctor_id = a.doctor_id
WHERE p.email = 'kerem.acar@hospital.test'
  AND a.appointment_time = TIME '14:30'
ON CONFLICT (appointment_id) DO NOTHING;

INSERT INTO Prescription (record_id, prescription_no, medication_name, dosage, duration, notes)
SELECT mr.record_id, 1, 'Ibuprofen', '400 mg', '5 days', 'Take after meals'
FROM MedicalRecord mr
JOIN Patient p ON p.patient_id = mr.patient_id
WHERE p.email = 'kerem.acar@hospital.test'
ON CONFLICT (record_id, prescription_no) DO NOTHING;

INSERT INTO Prescription (record_id, prescription_no, medication_name, dosage, duration, notes)
SELECT mr.record_id, 2, 'Magnesium', '250 mg', '30 days', 'One tablet daily'
FROM MedicalRecord mr
JOIN Patient p ON p.patient_id = mr.patient_id
WHERE p.email = 'kerem.acar@hospital.test'
ON CONFLICT (record_id, prescription_no) DO NOTHING;

-- ------------------------------------------------------------
-- Room assignment. Trigger marks E101 unavailable.
-- ------------------------------------------------------------
INSERT INTO RoomAssignment (patient_id, room_id, check_in_date, is_active)
SELECT p.patient_id, r.room_id, CURRENT_DATE, TRUE
FROM Patient p, Room r
WHERE p.email = 'duru.yilmaz@hospital.test'
  AND r.room_number = 'E101'
  AND NOT EXISTS (
      SELECT 1 FROM RoomAssignment ra
      WHERE ra.patient_id = p.patient_id AND ra.is_active = TRUE
  );

-- ------------------------------------------------------------
-- Billing
-- ------------------------------------------------------------
INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, billing_date, payment_date, description)
SELECT p.patient_id, a.appointment_id, 750.00, 'paid', CURRENT_DATE, CURRENT_DATE, 'Neurology consultation fee'
FROM Patient p
JOIN Appointment a ON a.patient_id = p.patient_id
WHERE p.email = 'kerem.acar@hospital.test'
  AND a.appointment_time = TIME '14:30'
ON CONFLICT (appointment_id) DO UPDATE
SET amount = EXCLUDED.amount,
    payment_status = EXCLUDED.payment_status,
    payment_date = EXCLUDED.payment_date,
    description = EXCLUDED.description;

INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, billing_date, description)
SELECT p.patient_id, a.appointment_id, 250.00, 'pending', CURRENT_DATE, 'Cardiology check deposit'
FROM Patient p
JOIN Appointment a ON a.patient_id = p.patient_id
WHERE p.email = 'duru.yilmaz@hospital.test'
  AND a.appointment_time = TIME '09:00'
ON CONFLICT (appointment_id) DO UPDATE
SET amount = EXCLUDED.amount,
    payment_status = EXCLUDED.payment_status,
    description = EXCLUDED.description;

-- ------------------------------------------------------------
-- Demo users. Password for all non-admin mock users: demo123
-- ------------------------------------------------------------
DELETE FROM AppUser
WHERE username IN ('doctor_demo', 'nurse_demo', 'patient_demo', 'billing_demo');

INSERT INTO AppUser (username, password_hash, role, doctor_id)
SELECT
    'aylin.demir',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'doctor',
    doctor_id
FROM Doctor
WHERE email = 'aylin.demir@hospital.test'
ON CONFLICT (username) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    doctor_id = EXCLUDED.doctor_id,
    nurse_id = NULL,
    patient_id = NULL,
    staff_id = NULL,
    is_active = TRUE;

INSERT INTO AppUser (username, password_hash, role, doctor_id)
SELECT
    'mert.kaya',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'doctor',
    doctor_id
FROM Doctor
WHERE email = 'mert.kaya@hospital.test'
ON CONFLICT (username) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    doctor_id = EXCLUDED.doctor_id,
    nurse_id = NULL,
    patient_id = NULL,
    staff_id = NULL,
    is_active = TRUE;

INSERT INTO AppUser (username, password_hash, role, nurse_id)
SELECT
    'selin.arslan',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'nurse',
    nurse_id
FROM Nurse
WHERE email = 'selin.arslan@hospital.test'
ON CONFLICT (username) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    doctor_id = NULL,
    nurse_id = EXCLUDED.nurse_id,
    patient_id = NULL,
    staff_id = NULL,
    is_active = TRUE;

INSERT INTO AppUser (username, password_hash, role, patient_id)
SELECT
    'duru.yilmaz',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'patient',
    patient_id
FROM Patient
WHERE email = 'duru.yilmaz@hospital.test'
ON CONFLICT (username) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    doctor_id = NULL,
    nurse_id = NULL,
    patient_id = EXCLUDED.patient_id,
    staff_id = NULL,
    is_active = TRUE;

INSERT INTO AppUser (username, password_hash, role)
VALUES (
    'buse.billing',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'billing_staff'
)
ON CONFLICT (username) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    doctor_id = NULL,
    nurse_id = NULL,
    patient_id = NULL,
    staff_id = NULL,
    is_active = TRUE;
