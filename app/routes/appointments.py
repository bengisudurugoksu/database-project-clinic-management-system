from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query
from app.auth_utils import login_required, role_required

appointments_bp = Blueprint("appointments", __name__)

@appointments_bp.route("/")
@login_required
def list_appointments():
    role = session.get("role")
    if role == "doctor":
        appointments = query(
            """SELECT * FROM view_doctor_schedule
               WHERE doctor_id = %s
               ORDER BY appointment_date DESC, appointment_time DESC""",
            (session["doctor_id"],), fetchall=True)
    elif role == "patient":
        appointments = query(
            """SELECT * FROM view_doctor_schedule
               WHERE patient_id = %s
               ORDER BY appointment_date DESC, appointment_time DESC""",
            (session["patient_id"],), fetchall=True)
    else:
        appointments = query(
            """SELECT * FROM view_doctor_schedule
               ORDER BY appointment_date DESC, appointment_time DESC""",
            fetchall=True)
    return render_template("appointments/list.html", appointments=appointments)

@appointments_bp.route("/add", methods=["GET", "POST"])
@role_required("admin", "nurse")
def add_appointment():
    patients = query("SELECT patient_id, first_name, last_name FROM Patient ORDER BY last_name", fetchall=True)
    doctors  = query("SELECT doctor_id, first_name, last_name, specialty FROM Doctor ORDER BY last_name", fetchall=True)
    if request.method == "POST":
        f = request.form
        try:
            query(
                """INSERT INTO Appointment (patient_id, doctor_id, appointment_date, appointment_time, notes)
                   VALUES (%s,%s,%s,%s,%s)""",
                (f["patient_id"], f["doctor_id"], f["appointment_date"],
                 f["appointment_time"], f.get("notes")),
                commit=True)
            flash("Appointment scheduled successfully.", "success")
            return redirect(url_for("appointments.list_appointments"))
        except Exception as e:
            flash(f"Error: {e}", "danger")
    return render_template("appointments/add.html", patients=patients, doctors=doctors)

@appointments_bp.route("/<int:appointment_id>/status", methods=["POST"])
@role_required("admin", "doctor", "nurse")
def update_status(appointment_id):
    status = request.form["status"]
    if status == "completed":
        flash("Use the Complete button so appointment completion and billing are committed atomically.", "warning")
        return redirect(url_for("appointments.list_appointments"))

    appt = query("SELECT appointment_id, doctor_id FROM Appointment WHERE appointment_id = %s",
                 (appointment_id,), fetchone=True)
    if not appt:
        flash("Appointment not found.", "danger")
        return redirect(url_for("appointments.list_appointments"))
    if session.get("role") == "doctor" and appt["doctor_id"] != session.get("doctor_id"):
        flash("You can only update your own appointments.", "danger")
        return redirect(url_for("appointments.list_appointments"))

    query("UPDATE Appointment SET status = %s WHERE appointment_id = %s",
          (status, appointment_id), commit=True)
    flash("Status updated.", "success")
    return redirect(url_for("appointments.list_appointments"))
