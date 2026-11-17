from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query
from app.auth_utils import login_required, role_required

patients_bp = Blueprint("patients", __name__)

@patients_bp.route("/")
@login_required
def list_patients():
    role = session.get("role")
    if role == "patient":
        # Patient sees only their own summary row from the view
        patients = query("SELECT * FROM view_patient_summary WHERE patient_id = %s",
                         (session["patient_id"],), fetchall=True)
    else:
        # Admin/doctor/nurse see the full summary view
        patients = query("SELECT * FROM view_patient_summary ORDER BY full_name", fetchall=True)
    return render_template("patients/list.html", patients=patients)

@patients_bp.route("/<int:patient_id>")
@login_required
def patient_detail(patient_id):
    if session.get("role") == "patient" and session.get("patient_id") != patient_id:
        flash("Access denied.", "danger")
        return redirect(url_for("patients.list_patients"))

    patient  = query("SELECT * FROM Patient WHERE patient_id = %s", (patient_id,), fetchone=True)

    # TABLE FUNCTION — returns full history (appointments + diagnosis + medications + billing) in one call
    full_history = query(
        "SELECT * FROM get_patient_appointments_full(%s)",
        (patient_id,), fetchall=True)

    billing = query(
        "SELECT * FROM view_billing_summary WHERE patient_id = %s ORDER BY billing_date DESC",
        (patient_id,), fetchall=True)

    # Scalar DB functions
    total_bill       = query("SELECT calculate_patient_bill(%s) AS val", (patient_id,), fetchone=True)["val"]
    outstanding_bill = query("SELECT calculate_outstanding_bill(%s) AS val", (patient_id,), fetchone=True)["val"]
    patient_age      = query("SELECT get_patient_age(%s) AS val", (patient_id,), fetchone=True)["val"]

    return render_template("patients/detail.html",
                           patient=patient, full_history=full_history,
                           billing=billing,
                           total_bill=total_bill, outstanding_bill=outstanding_bill,
                           patient_age=patient_age)

@patients_bp.route("/add", methods=["GET", "POST"])
@role_required("admin", "nurse")
def add_patient():
    if request.method == "POST":
        f = request.form
        try:
            query(
                """WITH new_person AS (
                       INSERT INTO Person (first_name, last_name, phone, email, person_type)
                       VALUES (%s, %s, %s, %s, 'patient')
                       RETURNING person_id
                   )
                   INSERT INTO Patient (person_id, first_name, last_name, date_of_birth, gender, blood_type,
                                        phone, email, address, emergency_contact_name, emergency_contact_phone)
                   SELECT person_id, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                   FROM new_person""",
                (f["first_name"], f["last_name"], f.get("phone") or None, f.get("email") or None,
                 f["first_name"], f["last_name"], f["date_of_birth"], f.get("gender") or None,
                 f.get("blood_type") or None, f.get("phone") or None, f.get("email") or None,
                 f.get("address") or None, f.get("emergency_contact_name") or None,
                 f.get("emergency_contact_phone") or None),
                commit=True)
            flash("Patient added successfully.", "success")
            return redirect(url_for("patients.list_patients"))
        except Exception as e:
            flash(f"Could not add patient: {e}", "danger")
    return render_template("patients/add.html")
