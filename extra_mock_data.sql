-- ============================================================
-- Extended mock data — demonstrates all view join scenarios
-- Run AFTER schema.sql, db_objects.sql, mock_data.sql
-- All new user passwords: demo123
-- ============================================================

-- ── New departments ──────────────────────────────────────────
INSERT INTO Department (name, location, phone)
VALUES
    ('Orthopedics', 'Block C - Floor 1', '0216-100-2004'),
    ('Dermatology',  'Block D - Floor 2', '0216-100-2005'),
    ('Pediatrics',   'Block A - Floor 1', '0216-100-2006')
ON CONFLICT (name) DO NOTHING;

-- ── New people ───────────────────────────────────────────────
INSERT INTO Person (first_name, last_name, phone, email, person_type)
VALUES
    ('Elif',   'Sahin',   '555-1010', 'elif.sahin@hospital.test',   'doctor'),
    ('Can',    'Dogan',   '555-1011', 'can.dogan@hospital.test',    'doctor'),
    ('Lale',   'Ozturk',  '555-1012', 'lale.ozturk@hospital.test',  'doctor'),
    ('Ahmet',  'Yildiz',  '555-2010', 'ahmet.yildiz@hospital.test', 'patient'),
    ('Fatma',  'Kaya',    '555-2011', 'fatma.kaya2@hospital.test',  'patient'),
    ('Zeynep', 'Celik',   '555-2012', 'zeynep.celik@hospital.test', 'patient'),
    ('Burak',  'Arslan',  '555-1013', 'burak.arslan@hospital.test', 'nurse')
ON CONFLICT (email) DO NOTHING;

-- ── New doctors ──────────────────────────────────────────────
-- Dr. Elif Sahin — Orthopedics (will have 1 appointment)
INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, 'Orthopedic Surgeon', p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'elif.sahin@hospital.test' AND d.name = 'Orthopedics'
ON CONFLICT (email) DO NOTHING;

-- Dr. Can Dogan — Dermatology (ZERO appointments → shows NULL row in RIGHT JOIN)
INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, 'Dermatologist', p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'can.dogan@hospital.test' AND d.name = 'Dermatology'
ON CONFLICT (email) DO NOTHING;

-- Dr. Lale Ozturk — Pediatrics (ZERO appointments → shows NULL row in RIGHT JOIN)
INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, 'Pediatrician', p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'lale.ozturk@hospital.test' AND d.name = 'Pediatrics'
ON CONFLICT (email) DO NOTHING;

-- ── New patients ─────────────────────────────────────────────
INSERT INTO Patient (person_id, first_name, last_name, date_of_birth, gender, blood_type,
                     phone, email, address, emergency_contact_name, emergency_contact_phone)
SELECT person_id, first_name, last_name, DATE '1975-03-15', 'M', 'B+',
       phone, email, 'Uskudar, Istanbul', 'Elif Yildiz', '555-3001'
FROM Person WHERE email = 'ahmet.yildiz@hospital.test'
ON CONFLICT (person_id) DO NOTHING;

INSERT INTO Patient (person_id, first_name, last_name, date_of_birth, gender, blood_type,
                     phone, email, address, emergency_contact_name, emergency_contact_phone)
SELECT person_id, first_name, last_name, DATE '1990-07-22', 'F', 'AB+',
       phone, email, 'Sisli, Istanbul', 'Mehmet Kaya', '555-3002'
FROM Person WHERE email = 'fatma.kaya2@hospital.test'
ON CONFLICT (person_id) DO NOTHING;

INSERT INTO Patient (person_id, first_name, last_name, date_of_birth, gender, blood_type,
                     phone, email, address, emergency_contact_name, emergency_contact_phone)
SELECT person_id, first_name, last_name, DATE '2005-11-08', 'F', 'O+',
       phone, email, 'Sariyer, Istanbul', 'Hasan Celik', '555-3003'
FROM Person WHERE email = 'zeynep.celik@hospital.test'
ON CONFLICT (person_id) DO NOTHING;

-- ── New nurse ────────────────────────────────────────────────
INSERT INTO Nurse (person_id, first_name, last_name, phone, email, department_id)
SELECT p.person_id, p.first_name, p.last_name, p.phone, p.email, d.department_id
FROM Person p, Department d
WHERE p.email = 'burak.arslan@hospital.test' AND d.name = 'Orthopedics'
ON CONFLICT (email) DO NOTHING;

-- ── Appointments ─────────────────────────────────────────────

-- 1. Completed — will have a bill → report_status: appointment_with_bill
INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id,
       CURRENT_DATE - 5, TIME '10:00', 'completed', 'Knee pain evaluation'
FROM Patient p, Doctor d
WHERE p.email = 'ahmet.yildiz@hospital.test' AND d.email = 'elif.sahin@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.appointment_date = CURRENT_DATE - 5 AND a.appointment_time = TIME '10:00');

-- 2. Scheduled, future — NO billing yet → report_status: appointment_without_bill
INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id,
       CURRENT_DATE + 3, TIME '11:00', 'scheduled', 'Annual dermatology check'
FROM Patient p, Doctor d
WHERE p.email = 'fatma.kaya2@hospital.test' AND d.email = 'elif.sahin@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.appointment_date = CURRENT_DATE + 3 AND a.appointment_time = TIME '11:00');

-- 3. Scheduled, future — NO billing → report_status: appointment_without_bill
INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id,
       CURRENT_DATE + 7, TIME '15:00', 'scheduled', 'Pediatric routine check-up'
FROM Patient p, Doctor d
WHERE p.email = 'zeynep.celik@hospital.test' AND d.email = 'elif.sahin@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.appointment_date = CURRENT_DATE + 7 AND a.appointment_time = TIME '15:00');

-- 4. Cancelled — NO billing → report_status: appointment_without_bill
INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, status, notes)
SELECT p.patient_id, d.doctor_id,
       CURRENT_DATE - 2, TIME '08:30', 'cancelled', 'Patient did not attend'
FROM Patient p, Doctor d
WHERE p.email = 'ahmet.yildiz@hospital.test' AND d.email = 'mert.kaya@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Appointment a
      WHERE a.patient_id = p.patient_id
        AND a.appointment_date = CURRENT_DATE - 2 AND a.appointment_time = TIME '08:30');

-- ── Billing ──────────────────────────────────────────────────

-- Bill for Ahmet's completed orthopedics visit → appointment_with_bill
INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, billing_date, description)
SELECT p.patient_id, a.appointment_id, 1200.00, 'pending', CURRENT_DATE - 5,
       'Orthopedic evaluation and X-ray fee'
FROM Patient p
JOIN Appointment a ON a.patient_id = p.patient_id
WHERE p.email = 'ahmet.yildiz@hospital.test'
  AND a.appointment_date = CURRENT_DATE - 5 AND a.appointment_time = TIME '10:00'
ON CONFLICT (appointment_id) DO UPDATE
SET amount = EXCLUDED.amount, description = EXCLUDED.description;

-- Standalone bill with appointment_id = NULL → report_status: bill_without_appointment
-- (simulates a walk-in charge or a bill whose appointment was later deleted)
INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, billing_date, description)
SELECT p.patient_id, NULL, 350.00, 'pending', CURRENT_DATE - 1,
       'Emergency walk-in fee (no appointment record)'
FROM Patient p
WHERE p.email = 'zeynep.celik@hospital.test'
  AND NOT EXISTS (
      SELECT 1 FROM Billing b
      WHERE b.patient_id = p.patient_id AND b.appointment_id IS NULL);

-- ── Medical records & prescriptions ─────────────────────────
INSERT INTO MedicalRecord (patient_id, doctor_id, appointment_id, diagnosis, notes)
SELECT p.patient_id, d.doctor_id, a.appointment_id,
       'Knee osteoarthritis — Grade II',
       'Recommend physiotherapy 3x/week for 6 weeks. Follow-up in 6 weeks.'
FROM Patient p
JOIN Appointment a ON a.patient_id = p.patient_id
JOIN Doctor d ON d.doctor_id = a.doctor_id
WHERE p.email = 'ahmet.yildiz@hospital.test'
  AND a.appointment_date = CURRENT_DATE - 5
ON CONFLICT (appointment_id) DO NOTHING;

INSERT INTO Prescription (record_id, prescription_no, medication_name, dosage, duration, notes)
SELECT mr.record_id, 1, 'Naproxen', '500 mg', '10 days', 'Take twice daily with food'
FROM MedicalRecord mr
JOIN Patient p ON p.patient_id = mr.patient_id
WHERE p.email = 'ahmet.yildiz@hospital.test'
ON CONFLICT (record_id, prescription_no) DO NOTHING;

INSERT INTO Prescription (record_id, prescription_no, medication_name, dosage, duration, notes)
SELECT mr.record_id, 2, 'Glucosamine', '1500 mg', '90 days', 'Once daily at breakfast'
FROM MedicalRecord mr
JOIN Patient p ON p.patient_id = mr.patient_id
WHERE p.email = 'ahmet.yildiz@hospital.test'
ON CONFLICT (record_id, prescription_no) DO NOTHING;

-- ── New rooms ────────────────────────────────────────────────
INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'C101', 'General', 2, TRUE, department_id FROM Department WHERE name = 'Orthopedics'
ON CONFLICT (room_number) DO NOTHING;

INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'D201', 'Private', 1, TRUE, department_id FROM Department WHERE name = 'Dermatology'
ON CONFLICT (room_number) DO NOTHING;

INSERT INTO Room (room_number, room_type, capacity, is_available, department_id)
SELECT 'A102', 'Pediatric', 4, TRUE, department_id FROM Department WHERE name = 'Pediatrics'
ON CONFLICT (room_number) DO NOTHING;

-- ── App users for new doctors/patients ───────────────────────
INSERT INTO AppUser (username, password_hash, role, doctor_id)
SELECT 'elif.sahin',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'doctor', doctor_id
FROM Doctor WHERE email = 'elif.sahin@hospital.test'
ON CONFLICT (username) DO NOTHING;

INSERT INTO AppUser (username, password_hash, role, doctor_id)
SELECT 'can.dogan',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'doctor', doctor_id
FROM Doctor WHERE email = 'can.dogan@hospital.test'
ON CONFLICT (username) DO NOTHING;

INSERT INTO AppUser (username, password_hash, role, patient_id)
SELECT 'ahmet.yildiz',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'patient', patient_id
FROM Patient WHERE email = 'ahmet.yildiz@hospital.test'
ON CONFLICT (username) DO NOTHING;

INSERT INTO AppUser (username, password_hash, role, patient_id)
SELECT 'fatma.kaya2',
    'scrypt:32768:8:1$ZPsXms4awluhuLxV$3344efec902d027b5f4a8193080c7858c06c04373631a3ec4487c3d014f521b0be113f97de7f0f7e93266e2e98e051d19cdc28181fe6240edc58ecd6add8cc46',
    'patient', patient_id
FROM Patient WHERE email = 'fatma.kaya2@hospital.test'
ON CONFLICT (username) DO NOTHING;
