-- Run this as postgres superuser:
-- sudo -u postgres psql -d hospital_db -f roles.sql

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

-- Remove default public access, then grant only the project roles.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO role_admin, role_doctor, role_nurse, role_billing_staff, role_patient;

-- Admin: full access
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO role_doctor, role_nurse, role_billing_staff;

-- Doctor
GRANT SELECT ON Patient, Department, Room, Doctor, Nurse TO role_doctor;
GRANT SELECT, INSERT, UPDATE ON Appointment TO role_doctor;
GRANT SELECT, INSERT, UPDATE ON MedicalRecord TO role_doctor;
GRANT SELECT, INSERT ON Prescription TO role_doctor;
GRANT SELECT ON Billing TO role_doctor;

-- Nurse
GRANT SELECT ON Patient, Doctor, Department TO role_nurse;
GRANT SELECT, INSERT, UPDATE ON Appointment TO role_nurse;
GRANT SELECT, INSERT, UPDATE ON RoomAssignment TO role_nurse;
GRANT SELECT, UPDATE ON Room TO role_nurse;

-- Billing staff
GRANT SELECT, INSERT, UPDATE ON Billing TO role_billing_staff;
GRANT SELECT ON Patient TO role_billing_staff;
GRANT SELECT ON Appointment TO role_billing_staff;

-- Patient
GRANT SELECT ON Appointment TO role_patient;
GRANT SELECT ON MedicalRecord TO role_patient;
GRANT SELECT ON Prescription TO role_patient;
GRANT SELECT ON Billing TO role_patient;
GRANT SELECT ON Doctor, Department TO role_patient;
GRANT SELECT ON Person TO role_admin, role_doctor, role_nurse, role_billing_staff;

-- Grant view access
GRANT SELECT ON view_doctor_schedule   TO role_doctor, role_nurse, role_admin;
GRANT SELECT ON view_person_specialization TO role_admin, role_doctor, role_nurse, role_billing_staff;
GRANT SELECT ON view_patient_summary   TO role_admin, role_doctor, role_nurse;
GRANT SELECT ON view_billing_summary   TO role_billing_staff, role_admin;
GRANT SELECT ON view_room_availability TO role_admin, role_nurse, role_doctor;
GRANT SELECT ON view_department_stats  TO role_admin, role_doctor, role_nurse;
GRANT SELECT ON view_doctor_appointment_right_report TO role_admin, role_doctor, role_nurse, role_billing_staff;
GRANT SELECT ON view_patient_billing_full_report TO role_admin, role_billing_staff;
GRANT SELECT ON AuditLog               TO role_admin;

-- Grant function execution
GRANT EXECUTE ON FUNCTION calculate_patient_bill(INT)                    TO role_admin, role_billing_staff, role_doctor;
GRANT EXECUTE ON FUNCTION calculate_outstanding_bill(INT)                TO role_admin, role_billing_staff, role_doctor;
GRANT EXECUTE ON FUNCTION check_doctor_availability(INT, DATE, TIME)     TO role_admin, role_doctor, role_nurse;
GRANT EXECUTE ON FUNCTION count_doctor_patients(INT)                     TO role_admin, role_doctor;
GRANT EXECUTE ON FUNCTION get_patient_age(INT)                           TO role_admin, role_doctor, role_nurse;
GRANT EXECUTE ON FUNCTION get_patient_appointments_full(INT)             TO role_admin, role_doctor, role_nurse, role_patient;

-- Local Flask connection user from .env. This gives the application login
-- the admin role while preserving the project role structure.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hospital_admin') THEN
        GRANT role_admin TO hospital_admin;
    END IF;
END;
$$;
