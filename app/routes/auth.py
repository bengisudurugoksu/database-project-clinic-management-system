from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from werkzeug.security import generate_password_hash, check_password_hash
from app.db import query
from app.auth_utils import role_required

auth_bp = Blueprint("auth", __name__)

@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if "user_id" in session:
        return redirect(url_for("main.dashboard"))
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]
        user = query("SELECT * FROM AppUser WHERE username = %s AND is_active = TRUE",
                     (username,), fetchone=True)
        if user and check_password_hash(user["password_hash"], password):
            session["user_id"]  = user["user_id"]
            session["username"] = user["username"]
            session["role"]     = user["role"]
            session["doctor_id"]  = user["doctor_id"]
            session["patient_id"] = user["patient_id"]
            session["nurse_id"]   = user["nurse_id"]
            flash(f"Welcome back, {user['username']}!", "success")
            return redirect(url_for("main.dashboard"))
        flash("Invalid username or password.", "danger")
    return render_template("auth/login.html")

@auth_bp.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("auth.login"))

@auth_bp.route("/register", methods=["GET", "POST"])
@role_required("admin")
def register():
    """Admin-only: create new user accounts."""
    if request.method == "POST":
        f = request.form
        hashed = generate_password_hash(f["password"])
        try:
            query(
                """INSERT INTO AppUser (username, password_hash, role, doctor_id, nurse_id, patient_id, staff_id)
                   VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                (f["username"], hashed, f["role"],
                 f.get("doctor_id") or None, f.get("nurse_id") or None,
                 f.get("patient_id") or None, f.get("staff_id") or None),
                commit=True
            )
            flash("User created successfully.", "success")
            return redirect(url_for("auth.register"))
        except Exception as e:
            flash(f"Error: {e}", "danger")
    doctors  = query("SELECT doctor_id, first_name, last_name FROM Doctor ORDER BY last_name", fetchall=True)
    nurses   = query("SELECT nurse_id, first_name, last_name FROM Nurse ORDER BY last_name", fetchall=True)
    patients = query("SELECT patient_id, first_name, last_name FROM Patient ORDER BY last_name", fetchall=True)
    staff    = query("SELECT staff_id, first_name, last_name FROM Staff ORDER BY last_name", fetchall=True)
    return render_template("auth/register.html", doctors=doctors, nurses=nurses, patients=patients, staff=staff)
