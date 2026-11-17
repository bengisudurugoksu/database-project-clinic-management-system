from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query
from app.auth_utils import login_required, role_required

nurses_bp = Blueprint("nurses", __name__)

@nurses_bp.route("/")
@login_required
def list_nurses():
    nurses = query(
        """SELECT n.*, dept.name AS department_name
           FROM Nurse n LEFT JOIN Department dept ON n.department_id = dept.department_id
           ORDER BY n.last_name, n.first_name""",
        fetchall=True)
    return render_template("nurses/list.html", nurses=nurses)

@nurses_bp.route("/add", methods=["GET", "POST"])
@role_required("admin")
def add_nurse():
    departments = query("SELECT * FROM Department ORDER BY name", fetchall=True)
    if request.method == "POST":
        f = request.form
        try:
            query(
                """WITH new_person AS (
                       INSERT INTO Person (first_name, last_name, phone, email, person_type)
                       VALUES (%s, %s, %s, %s, 'nurse')
                       RETURNING person_id
                   )
                   INSERT INTO Nurse (person_id, first_name, last_name, phone, email, department_id)
                   SELECT person_id, %s, %s, %s, %s, %s
                   FROM new_person""",
                (f["first_name"], f["last_name"],
                 f.get("phone") or None, f.get("email") or None,
                 f["first_name"], f["last_name"],
                 f.get("phone") or None, f.get("email") or None,
                 f.get("department_id") or None),
                commit=True)
            flash("Nurse added successfully.", "success")
            return redirect(url_for("nurses.list_nurses"))
        except Exception as e:
            flash(f"Could not add nurse: {e}", "danger")
    return render_template("nurses/add.html", departments=departments)
