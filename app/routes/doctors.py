from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query
from app.auth_utils import login_required, role_required

doctors_bp = Blueprint("doctors", __name__)

@doctors_bp.route("/")
@login_required
def list_doctors():
    # Doctors go straight to their own profile
    if session.get("role") == "doctor":
        return redirect(url_for("doctors.doctor_detail", doctor_id=session["doctor_id"]))
    doctors = query(
        """SELECT d.*, dept.name AS department_name
           FROM Doctor d LEFT JOIN Department dept ON d.department_id = dept.department_id
           ORDER BY d.last_name, d.first_name""",
        fetchall=True)
    return render_template("doctors/list.html", doctors=doctors)

@doctors_bp.route("/<int:doctor_id>")
@login_required
def doctor_detail(doctor_id):
    # Doctors can only view their own profile
    if session.get("role") == "doctor" and session.get("doctor_id") != doctor_id:
        flash("You can only view your own profile.", "danger")
        return redirect(url_for("doctors.doctor_detail", doctor_id=session["doctor_id"]))
    doctor = query(
        """SELECT d.*, dept.name AS department_name
           FROM Doctor d LEFT JOIN Department dept ON d.department_id = dept.department_id
           WHERE d.doctor_id = %s""",
        (doctor_id,), fetchone=True)
    # Use view_doctor_schedule for rich appointment data
    appointments = query(
        """SELECT * FROM view_doctor_schedule
           WHERE doctor_id = %s ORDER BY appointment_date DESC, appointment_time DESC""",
        (doctor_id,), fetchall=True)
    patient_count = query("SELECT count_doctor_patients(%s) AS c", (doctor_id,), fetchone=True)["c"]
    return render_template("doctors/detail.html", doctor=doctor,
                           appointments=appointments, patient_count=patient_count)

@doctors_bp.route("/add", methods=["GET", "POST"])
@role_required("admin")
def add_doctor():
    departments = query("SELECT * FROM Department ORDER BY name", fetchall=True)
    if request.method == "POST":
        f = request.form
        try:
            query(
                """WITH new_person AS (
                       INSERT INTO Person (first_name, last_name, phone, email, person_type)
                       VALUES (%s, %s, %s, %s, 'doctor')
                       RETURNING person_id
                   )
                   INSERT INTO Doctor (person_id, first_name, last_name, specialty, phone, email, department_id)
                   SELECT person_id, %s, %s, %s, %s, %s, %s
                   FROM new_person""",
                (f["first_name"], f["last_name"],
                 f.get("phone") or None, f.get("email") or None,
                 f["first_name"], f["last_name"], f["specialty"],
                 f.get("phone") or None, f.get("email") or None,
                 f.get("department_id") or None),
                commit=True)
            flash("Doctor added successfully.", "success")
            return redirect(url_for("doctors.list_doctors"))
        except Exception as e:
            flash(f"Could not add doctor: {e}", "danger")
    return render_template("doctors/add.html", departments=departments)
