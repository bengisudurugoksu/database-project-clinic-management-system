from flask import Flask
import os
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

def create_app():
    app = Flask(__name__, template_folder="templates", static_folder="../static")
    app.secret_key = os.getenv("SECRET_KEY")

    from app.routes.auth import auth_bp
    from app.routes.main import main_bp
    from app.routes.patients import patients_bp
    from app.routes.doctors import doctors_bp
    from app.routes.nurses import nurses_bp
    from app.routes.appointments import appointments_bp
    from app.routes.billing import billing_bp
    from app.routes.rooms import rooms_bp
    from app.routes.transactions import transactions_bp
    from app.routes.reports import reports_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(main_bp)
    app.register_blueprint(patients_bp, url_prefix="/patients")
    app.register_blueprint(doctors_bp, url_prefix="/doctors")
    app.register_blueprint(nurses_bp, url_prefix="/nurses")
    app.register_blueprint(appointments_bp, url_prefix="/appointments")
    app.register_blueprint(billing_bp, url_prefix="/billing")
    app.register_blueprint(rooms_bp, url_prefix="/rooms")
    app.register_blueprint(transactions_bp, url_prefix="/transactions")
    app.register_blueprint(reports_bp, url_prefix="/reports")

    @app.context_processor
    def inject_now():
        return {"now": datetime.now()}

    return app
