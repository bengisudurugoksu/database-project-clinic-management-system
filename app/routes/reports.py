from flask import Blueprint, render_template
from app.db import query
from app.auth_utils import role_required

reports_bp = Blueprint("reports", __name__)


@reports_bp.route("/")
@role_required("admin", "doctor", "nurse", "billing_staff")
def list_reports():
    # INNER JOIN — only appointments that have both a doctor and a patient
    inner_join_rows = query(
        """SELECT *
           FROM view_doctor_schedule
           ORDER BY appointment_date DESC, appointment_time DESC""",
        fetchall=True)

    # LEFT OUTER JOIN — all rooms, even those with no current patient
    left_join_rows = query(
        """SELECT *
           FROM view_room_availability
           ORDER BY is_available DESC, room_number""",
        fetchall=True)

    # RIGHT OUTER JOIN — all doctors, even those with no appointments
    right_join_rows = query(
        """SELECT *
           FROM view_doctor_appointment_right_report
           ORDER BY doctor_name, appointment_date NULLS LAST, appointment_time NULLS LAST""",
        fetchall=True)

    # FULL OUTER JOIN — appointments and billing rows reconciled
    full_join_rows = query(
        """SELECT *
           FROM view_patient_billing_full_report
           ORDER BY report_status, appointment_id NULLS LAST""",
        fetchall=True)

    # Inheritance / specialisation view
    inheritance_rows = query(
        """SELECT *
           FROM view_person_specialization
           ORDER BY person_type, last_name, first_name""",
        fetchall=True)

    summary = {
        "total_appointments": len(inner_join_rows),
        "available_rooms":    len([r for r in left_join_rows if r["is_available"]]),
        "doctors_no_appt":    len([r for r in right_join_rows if not r["appointment_id"]]),
        "appts_without_bill": len([r for r in full_join_rows if r["report_status"] == "appointment_without_bill"]),
    }

    return render_template(
        "reports/list.html",
        inner_join_rows=inner_join_rows,
        left_join_rows=left_join_rows,
        right_join_rows=right_join_rows,
        full_join_rows=full_join_rows,
        inheritance_rows=inheritance_rows,
        summary=summary,
    )
