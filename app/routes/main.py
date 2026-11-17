from flask import Blueprint, render_template, session
from app.db import query
from app.auth_utils import login_required

main_bp = Blueprint("main", __name__)

@main_bp.route("/")
@login_required
def dashboard():
    role = session.get("role")

    if role == "patient":
        pid = session.get("patient_id")
        stats = {
            "my_appointments":   query("SELECT COUNT(*) AS c FROM Appointment WHERE patient_id = %s", (pid,), fetchone=True)["c"],
            "appointments_today": query("SELECT COUNT(*) AS c FROM Appointment WHERE patient_id = %s AND appointment_date = CURRENT_DATE", (pid,), fetchone=True)["c"],
            "total_billed":      query("SELECT calculate_patient_bill(%s) AS c", (pid,), fetchone=True)["c"],
            "outstanding":       query("SELECT calculate_outstanding_bill(%s) AS c", (pid,), fetchone=True)["c"],
        }
        dept_stats = []
        todays = query(
            """SELECT * FROM view_doctor_schedule
               WHERE patient_id = %s AND appointment_date = CURRENT_DATE
               ORDER BY appointment_time""",
            (pid,), fetchall=True)

    elif role == "doctor":
        did = session.get("doctor_id")
        stats = {
            "my_patients":        query("SELECT count_doctor_patients(%s) AS c", (did,), fetchone=True)["c"],
            "appointments_today": query("SELECT COUNT(*) AS c FROM Appointment WHERE doctor_id = %s AND appointment_date = CURRENT_DATE", (did,), fetchone=True)["c"],
            "available_rooms":    query("SELECT COUNT(*) AS c FROM Room WHERE is_available = TRUE", fetchone=True)["c"],
            "total_appointments": query("SELECT COUNT(*) AS c FROM Appointment WHERE doctor_id = %s", (did,), fetchone=True)["c"],
        }
        dept_stats = query("SELECT * FROM view_department_stats ORDER BY department_name", fetchall=True)
        todays = query(
            """SELECT * FROM view_doctor_schedule
               WHERE appointment_date = CURRENT_DATE AND doctor_id = %s
               ORDER BY appointment_time""",
            (did,), fetchall=True)

    else:
        stats = {
            "patients":           query("SELECT COUNT(*) AS c FROM Patient", fetchone=True)["c"],
            "doctors":            query("SELECT COUNT(*) AS c FROM Doctor", fetchone=True)["c"],
            "appointments_today": query("SELECT COUNT(*) AS c FROM Appointment WHERE appointment_date = CURRENT_DATE", fetchone=True)["c"],
            "available_rooms":    query("SELECT COUNT(*) AS c FROM Room WHERE is_available = TRUE", fetchone=True)["c"],
        }
        dept_stats = query("SELECT * FROM view_department_stats ORDER BY department_name", fetchall=True) if role in ("admin", "nurse") else []
        todays = query(
            """SELECT * FROM view_doctor_schedule
               WHERE appointment_date = CURRENT_DATE
               ORDER BY appointment_time""",
            fetchall=True)

    return render_template("dashboard.html", stats=stats, dept_stats=dept_stats, todays=todays, role=role)
