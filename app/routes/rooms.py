from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query
from app.auth_utils import login_required, role_required

rooms_bp = Blueprint("rooms", __name__)

@rooms_bp.route("/")
@login_required
def list_rooms():
    # Use view_room_availability
    rooms = query("SELECT * FROM view_room_availability ORDER BY room_number", fetchall=True)
    return render_template("rooms/list.html", rooms=rooms)

@rooms_bp.route("/discharge/<int:assignment_id>", methods=["POST"])
@role_required("admin", "nurse")
def discharge_patient(assignment_id):
    rowcount = query(
        """UPDATE RoomAssignment
           SET is_active = FALSE, check_out_date = CURRENT_DATE
           WHERE assignment_id = %s AND is_active = TRUE""",
        (assignment_id,), commit=True)
    if rowcount:
        flash("Patient discharged. Room is now available.", "success")
    else:
        flash("No active room assignment was found.", "warning")
    return redirect(url_for("rooms.list_rooms"))

@rooms_bp.route("/add", methods=["GET", "POST"])
@role_required("admin")
def add_room():
    departments = query("SELECT * FROM Department ORDER BY name", fetchall=True)
    if request.method == "POST":
        f = request.form
        try:
            query(
                """INSERT INTO Room (room_number, room_type, capacity, department_id)
                   VALUES (%s,%s,%s,%s)""",
                (f["room_number"], f["room_type"], f["capacity"], f.get("department_id") or None),
                commit=True)
            flash("Room added successfully.", "success")
            return redirect(url_for("rooms.list_rooms"))
        except Exception as e:
            flash(f"Could not add room: {e}", "danger")
    return render_template("rooms/add.html", departments=departments)
