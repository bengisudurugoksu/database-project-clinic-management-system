from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query, run_transaction
from app.auth_utils import role_required

transactions_bp = Blueprint("transactions", __name__)

# ------------------------------------------------------------------
# TRANSACTION 1 — Admit Patient
# Atomically: assign a room  +  create an initial appointment
# If either step fails, both are rolled back.
# ------------------------------------------------------------------
@transactions_bp.route("/admit", methods=["GET", "POST"])
@role_required("admin", "nurse")
def admit_patient():
    patients = query(
        """SELECT patient_id, first_name, last_name
           FROM Patient
           WHERE patient_id NOT IN (
               SELECT patient_id FROM RoomAssignment WHERE is_active = TRUE
           )
           ORDER BY last_name""",
        fetchall=True)
    rooms    = query("SELECT room_id, room_number, room_type FROM Room WHERE is_available = TRUE ORDER BY room_number", fetchall=True)
    doctors  = query("SELECT doctor_id, first_name, last_name, specialty FROM Doctor ORDER BY last_name", fetchall=True)

    if request.method == "POST":
        f = request.form
        try:
            run_transaction([
                # Concurrency control: lock the selected available room so two
                # nurses cannot admit different patients into it at the same time.
                ("""SELECT room_id
                    FROM Room
                    WHERE room_id = %s AND is_available = TRUE
                    FOR UPDATE""",
                 (f["room_id"],), 1),

                # Concurrency control: lock the doctor row before scheduling.
                ("""SELECT doctor_id
                    FROM Doctor
                    WHERE doctor_id = %s
                    FOR UPDATE""",
                 (f["doctor_id"],), 1),

                # Step 1: assign room to patient
                ("""INSERT INTO RoomAssignment (patient_id, room_id, check_in_date, is_active)
                    VALUES (%s, %s, CURRENT_DATE, TRUE)""",
                 (f["patient_id"], f["room_id"]), 1),

                # Step 2: create initial appointment (same transaction — both or neither)
                ("""INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, notes)
                    VALUES (%s, %s, %s, %s, %s)""",
                 (f["patient_id"], f["doctor_id"],
                  f["appointment_date"], f["appointment_time"],
                  f.get("notes", "Admission appointment")), 1),
            ])
            flash("Patient admitted and appointment created successfully. (Atomic transaction committed)", "success")
            return redirect(url_for("transactions.admit_patient"))
        except Exception as e:
            flash(f"Transaction rolled back — admission failed: {e}", "danger")

    return render_template("transactions/admit.html",
                           patients=patients, rooms=rooms, doctors=doctors)


# ------------------------------------------------------------------
# TRANSACTION 2 — Complete Appointment
# Atomically: create/update billing record  +  mark appointment as completed
# Ensures revenue is never lost if billing insert fails.
# ------------------------------------------------------------------
@transactions_bp.route("/complete/<int:appointment_id>", methods=["POST"])
@role_required("admin", "doctor", "nurse")
def complete_appointment(appointment_id):
    amount = request.form.get("amount", 0)
    description = request.form.get("description", "Appointment fee")

    appt = query("SELECT * FROM Appointment WHERE appointment_id = %s",
                 (appointment_id,), fetchone=True)
    if not appt:
        flash("Appointment not found.", "danger")
        return redirect(url_for("appointments.list_appointments"))
    if session.get("role") == "doctor" and appt["doctor_id"] != session.get("doctor_id"):
        flash("You can only complete your own appointments.", "danger")
        return redirect(url_for("appointments.list_appointments"))
    if appt["status"] != "scheduled":
        flash("Only scheduled appointments can be completed atomically.", "warning")
        return redirect(url_for("appointments.list_appointments"))

    try:
        run_transaction([
            # Concurrency control: lock the appointment row being completed.
            ("""SELECT appointment_id
                FROM Appointment
                WHERE appointment_id = %s AND status = 'scheduled'
                FOR UPDATE""",
             (appointment_id,), 1),

            # Step 1: create the billing record first.
            # The AFTER UPDATE trigger on Appointment also auto-creates a bill,
            # so this order prevents a zero-amount duplicate from being inserted.
            ("""INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, description)
                VALUES (%s, %s, %s, 'unpaid', %s)
                ON CONFLICT (appointment_id) DO UPDATE
                SET amount = EXCLUDED.amount,
                    payment_status = EXCLUDED.payment_status,
                    description = EXCLUDED.description""",
             (appt["patient_id"], appointment_id, amount, description), 1),

            # Step 2: mark appointment completed (must succeed with billing)
            ("""UPDATE Appointment SET status = 'completed'
                WHERE appointment_id = %s""",
             (appointment_id,), 1),
        ])
        flash("Appointment completed and bill created. (Atomic transaction committed)", "success")
    except Exception as e:
        flash(f"Transaction rolled back — completion failed: {e}", "danger")

    return redirect(url_for("appointments.list_appointments"))


# ------------------------------------------------------------------
# TRANSACTION 3 — Transfer Patient Between Rooms
# Atomically: close old room assignment  +  open new room assignment
# Ensures a patient is never left with no room or double-assigned.
# ------------------------------------------------------------------
@transactions_bp.route("/transfer", methods=["GET", "POST"])
@role_required("admin", "nurse")
def transfer_patient():
    # Patients who currently have an active room assignment
    admitted = query(
        """SELECT ra.assignment_id, ra.patient_id, ra.room_id,
                  p.first_name || ' ' || p.last_name AS patient_name,
                  r.room_number AS current_room
           FROM RoomAssignment ra
           JOIN Patient p ON ra.patient_id = p.patient_id
           JOIN Room    r ON ra.room_id    = r.room_id
           WHERE ra.is_active = TRUE
           ORDER BY patient_name""",
        fetchall=True)

    available_rooms = query(
        "SELECT room_id, room_number, room_type FROM Room WHERE is_available = TRUE ORDER BY room_number",
        fetchall=True)

    if request.method == "POST":
        f = request.form
        assignment_id = f["assignment_id"]
        new_room_id   = f["new_room_id"]

        # Look up current assignment to get patient/room
        current = query("SELECT * FROM RoomAssignment WHERE assignment_id = %s",
                        (assignment_id,), fetchone=True)
        if not current:
            flash("Assignment not found.", "danger")
            return redirect(url_for("transactions.transfer_patient"))

        try:
            run_transaction([
                # Concurrency control: lock current assignment and destination room.
                ("""SELECT assignment_id
                    FROM RoomAssignment
                    WHERE assignment_id = %s AND is_active = TRUE
                    FOR UPDATE""",
                 (assignment_id,), 1),

                ("""SELECT room_id
                    FROM Room
                    WHERE room_id = %s AND is_available = TRUE
                    FOR UPDATE""",
                 (new_room_id,), 1),

                # Step 1: close the current room assignment
                ("""UPDATE RoomAssignment
                    SET is_active = FALSE, check_out_date = CURRENT_DATE
                    WHERE assignment_id = %s""",
                 (assignment_id,), 1),

                # Step 2: open new room assignment (must succeed with step 1)
                ("""INSERT INTO RoomAssignment (patient_id, room_id, check_in_date, is_active)
                    VALUES (%s, %s, CURRENT_DATE, TRUE)""",
                 (current["patient_id"], new_room_id), 1),
            ])
            flash("Patient transferred successfully. (Atomic transaction committed)", "success")
            return redirect(url_for("transactions.transfer_patient"))
        except Exception as e:
            flash(f"Transaction rolled back — transfer failed: {e}", "danger")

    return render_template("transactions/transfer.html",
                           admitted=admitted, available_rooms=available_rooms)
