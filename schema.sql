-- ============================================================
--  Hospital & Clinic Management System
--  Relational Schema
-- ============================================================

-- --------------------------------------------------------
-- 1. PERSON SUPERTYPE
-- --------------------------------------------------------
-- Inheritance/specialization: shared identity data lives in Person.
-- Doctor, Nurse, Patient, and Staff are subtype entity sets that can link
-- to one Person row while keeping their existing role-specific attributes.
CREATE TABLE Person (
    person_id       SERIAL PRIMARY KEY,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    phone           VARCHAR(20),
    email           VARCHAR(100) UNIQUE,
    person_type     VARCHAR(20) NOT NULL CHECK (person_type IN ('doctor', 'nurse', 'patient', 'staff')),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------
-- 2. DEPARTMENT
-- --------------------------------------------------------
CREATE TABLE Department (
    department_id   SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    location        VARCHAR(100),
    phone           VARCHAR(20)
);

-- --------------------------------------------------------
-- 3. DOCTOR
-- --------------------------------------------------------
CREATE TABLE Doctor (
    doctor_id       SERIAL PRIMARY KEY,
    person_id       INT UNIQUE REFERENCES Person(person_id) ON DELETE SET NULL,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    specialty       VARCHAR(100) NOT NULL,
    phone           VARCHAR(20),
    email           VARCHAR(100) UNIQUE,
    department_id   INT REFERENCES Department(department_id) ON DELETE SET NULL
);

-- Department head added after Doctor table exists (avoids circular FK)
ALTER TABLE Department
    ADD COLUMN head_doctor_id INT REFERENCES Doctor(doctor_id) ON DELETE SET NULL;

-- --------------------------------------------------------
-- 4. NURSE
-- --------------------------------------------------------
CREATE TABLE Nurse (
    nurse_id        SERIAL PRIMARY KEY,
    person_id       INT UNIQUE REFERENCES Person(person_id) ON DELETE SET NULL,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    phone           VARCHAR(20),
    email           VARCHAR(100) UNIQUE,
    department_id   INT REFERENCES Department(department_id) ON DELETE SET NULL
);

-- --------------------------------------------------------
-- 5. STAFF  (admin, receptionist, lab tech, pharmacist)
-- --------------------------------------------------------
CREATE TABLE Staff (
    staff_id        SERIAL PRIMARY KEY,
    person_id       INT UNIQUE REFERENCES Person(person_id) ON DELETE SET NULL,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    role            VARCHAR(30) NOT NULL CHECK (role IN ('admin', 'receptionist', 'lab_technician', 'pharmacist')),
    phone           VARCHAR(20),
    email           VARCHAR(100) UNIQUE
);

-- --------------------------------------------------------
-- 6. PATIENT
-- --------------------------------------------------------
CREATE TABLE Patient (
    patient_id              SERIAL PRIMARY KEY,
    person_id               INT UNIQUE REFERENCES Person(person_id) ON DELETE SET NULL,
    first_name              VARCHAR(50) NOT NULL,
    last_name               VARCHAR(50) NOT NULL,
    date_of_birth           DATE NOT NULL,
    gender                  CHAR(1) CHECK (gender IN ('M', 'F', 'O')),
    blood_type              VARCHAR(3) CHECK (blood_type IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    phone                   VARCHAR(20),
    email                   VARCHAR(100),
    address                 TEXT,
    emergency_contact_name  VARCHAR(100),
    emergency_contact_phone VARCHAR(20),
    registered_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------
-- 7. ROOM
-- --------------------------------------------------------
CREATE TABLE Room (
    room_id         SERIAL PRIMARY KEY,
    room_number     VARCHAR(10) NOT NULL UNIQUE,
    room_type       VARCHAR(20) NOT NULL CHECK (room_type IN ('General', 'ICU', 'Surgery', 'Emergency', 'Pediatric', 'Private')),
    capacity        INT NOT NULL CHECK (capacity > 0),
    is_available    BOOLEAN DEFAULT TRUE,
    department_id   INT REFERENCES Department(department_id) ON DELETE SET NULL
);

-- --------------------------------------------------------
-- 8. APPOINTMENT
-- --------------------------------------------------------
CREATE TABLE Appointment (
    appointment_id  SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES Patient(patient_id) ON DELETE CASCADE,
    doctor_id       INT NOT NULL REFERENCES Doctor(doctor_id) ON DELETE RESTRICT,
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    status          VARCHAR(20) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled', 'no_show')),
    notes           TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------
-- 9. MEDICAL RECORD
-- --------------------------------------------------------
CREATE TABLE MedicalRecord (
    record_id       SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES Patient(patient_id) ON DELETE CASCADE,
    doctor_id       INT NOT NULL REFERENCES Doctor(doctor_id) ON DELETE RESTRICT,
    appointment_id  INT UNIQUE REFERENCES Appointment(appointment_id) ON DELETE SET NULL,
    diagnosis       TEXT NOT NULL,
    notes           TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------
-- 10. PRESCRIPTION
-- --------------------------------------------------------
CREATE TABLE Prescription (
    record_id       INT NOT NULL REFERENCES MedicalRecord(record_id) ON DELETE CASCADE,
    prescription_no INT NOT NULL CHECK (prescription_no > 0),
    medication_name VARCHAR(100) NOT NULL,
    dosage          VARCHAR(50) NOT NULL,
    duration        VARCHAR(50),
    notes           TEXT,
    PRIMARY KEY (record_id, prescription_no)
);

-- --------------------------------------------------------
-- 11. ROOM ASSIGNMENT  (tracks patient room history)
-- --------------------------------------------------------
CREATE TABLE RoomAssignment (
    assignment_id   SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES Patient(patient_id) ON DELETE CASCADE,
    room_id         INT NOT NULL REFERENCES Room(room_id) ON DELETE RESTRICT,
    check_in_date   DATE NOT NULL,
    check_out_date  DATE,
    is_active       BOOLEAN DEFAULT TRUE,
    CHECK (check_out_date IS NULL OR check_out_date >= check_in_date)
);

-- --------------------------------------------------------
-- 12. BILLING
-- --------------------------------------------------------
CREATE TABLE Billing (
    billing_id      SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES Patient(patient_id) ON DELETE CASCADE,
    appointment_id  INT UNIQUE REFERENCES Appointment(appointment_id) ON DELETE SET NULL,
    amount          NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    payment_status  VARCHAR(10) DEFAULT 'unpaid' CHECK (payment_status IN ('paid', 'unpaid', 'pending')),
    billing_date    DATE DEFAULT CURRENT_DATE,
    payment_date    DATE,
    description     TEXT
);

-- --------------------------------------------------------
-- 13. APP USER  (login accounts)
-- --------------------------------------------------------
CREATE TABLE AppUser (
    user_id       SERIAL PRIMARY KEY,
    username      VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(256) NOT NULL,
    role          VARCHAR(20) NOT NULL CHECK (role IN ('admin','doctor','nurse','billing_staff','patient')),
    doctor_id     INT REFERENCES Doctor(doctor_id) ON DELETE SET NULL,
    nurse_id      INT REFERENCES Nurse(nurse_id) ON DELETE SET NULL,
    patient_id    INT REFERENCES Patient(patient_id) ON DELETE SET NULL,
    staff_id      INT REFERENCES Staff(staff_id) ON DELETE SET NULL,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        (role = 'doctor' AND doctor_id IS NOT NULL AND nurse_id IS NULL AND patient_id IS NULL)
        OR (role = 'nurse' AND nurse_id IS NOT NULL AND doctor_id IS NULL AND patient_id IS NULL)
        OR (role = 'patient' AND patient_id IS NOT NULL AND doctor_id IS NULL AND nurse_id IS NULL)
        OR (role IN ('admin','billing_staff') AND doctor_id IS NULL AND nurse_id IS NULL AND patient_id IS NULL)
    )
);

-- --------------------------------------------------------
-- 14. AUDIT LOG  (written by triggers in db_objects.sql)
-- --------------------------------------------------------
CREATE TABLE AuditLog (
    log_id      SERIAL PRIMARY KEY,
    table_name  VARCHAR(50)  NOT NULL,
    action      VARCHAR(10)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    record_id   INT,
    changed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details     TEXT
);

-- --------------------------------------------------------
-- Physical design / integrity-supporting indexes
-- --------------------------------------------------------
-- A cancelled appointment frees the doctor slot; active/non-cancelled
-- appointments are still protected from double-booking.
CREATE UNIQUE INDEX uq_doctor_active_appointment_slot
    ON Appointment (doctor_id, appointment_date, appointment_time)
    WHERE status != 'cancelled';

CREATE INDEX idx_appointment_patient_date
    ON Appointment (patient_id, appointment_date DESC, appointment_time DESC);

CREATE INDEX idx_billing_patient_status
    ON Billing (patient_id, payment_status);

-- A patient can occupy only one active room, and a room can have only one
-- active assignment, while history rows remain unlimited.
CREATE UNIQUE INDEX uq_active_room_assignment_patient
    ON RoomAssignment (patient_id)
    WHERE is_active = TRUE;

CREATE UNIQUE INDEX uq_active_room_assignment_room
    ON RoomAssignment (room_id)
    WHERE is_active = TRUE;

-- Each real person/staff record should map to at most one login account.
CREATE UNIQUE INDEX uq_appuser_doctor
    ON AppUser (doctor_id)
    WHERE doctor_id IS NOT NULL;

CREATE UNIQUE INDEX uq_appuser_nurse
    ON AppUser (nurse_id)
    WHERE nurse_id IS NOT NULL;

CREATE UNIQUE INDEX uq_appuser_patient
    ON AppUser (patient_id)
    WHERE patient_id IS NOT NULL;

CREATE UNIQUE INDEX uq_appuser_staff
    ON AppUser (staff_id)
    WHERE staff_id IS NOT NULL;
