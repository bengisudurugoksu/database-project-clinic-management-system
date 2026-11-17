from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query
from app.auth_utils import role_required

billing_bp = Blueprint("billing", __name__)

@billing_bp.route("/")
@role_required("admin", "billing_staff")
def list_billing():
    # Use view_billing_summary
    bills = query("SELECT * FROM view_billing_summary ORDER BY billing_date DESC", fetchall=True)
    return render_template("billing/list.html", bills=bills)

@billing_bp.route("/add", methods=["GET", "POST"])
@role_required("admin", "billing_staff")
def add_billing():
    patients     = query("SELECT patient_id, first_name, last_name FROM Patient ORDER BY last_name", fetchall=True)
    appointments = query(
        """SELECT a.appointment_id, a.patient_id, a.appointment_date, a.status,
                  p.first_name || ' ' || p.last_name AS patient_name
           FROM Appointment a JOIN Patient p ON a.patient_id = p.patient_id
           WHERE a.appointment_id NOT IN (
               SELECT appointment_id FROM Billing WHERE appointment_id IS NOT NULL
           )
           ORDER BY a.appointment_date DESC""",
        fetchall=True)
    if request.method == "POST":
        f = request.form
        appointment_id = f.get("appointment_id") or None
        try:
            if appointment_id:
                appt = query("SELECT patient_id FROM Appointment WHERE appointment_id = %s",
                             (appointment_id,), fetchone=True)
                if not appt:
                    flash("Selected appointment was not found.", "danger")
                    return redirect(url_for("billing.add_billing"))
                if str(appt["patient_id"]) != f["patient_id"]:
                    flash("Selected appointment does not belong to the selected patient.", "danger")
                    return redirect(url_for("billing.add_billing"))

            query(
                """INSERT INTO Billing (patient_id, appointment_id, amount, payment_status, description)
                   VALUES (%s,%s,%s,%s,%s)""",
                (f["patient_id"], appointment_id,
                 f["amount"], f.get("payment_status", "unpaid"), f.get("description")),
                commit=True)
            flash("Bill created successfully.", "success")
            return redirect(url_for("billing.list_billing"))
        except Exception as e:
            flash(f"Could not create bill: {e}", "danger")
    return render_template("billing/add.html", patients=patients, appointments=appointments)

@billing_bp.route("/<int:billing_id>/pay", methods=["POST"])
@role_required("admin", "billing_staff")
def mark_paid(billing_id):
    query("UPDATE Billing SET payment_status = 'paid', payment_date = CURRENT_DATE WHERE billing_id = %s",
          (billing_id,), commit=True)
    flash("Payment recorded.", "success")
    return redirect(url_for("billing.list_billing"))
