import sys
from pathlib import Path
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Ensure both backend directory and project root are in Python path
file_path = Path(__file__).resolve()
backend_dir = file_path.parent
project_root = backend_dir.parent

if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

try:
    from backend.app.config import settings
    from backend.app.database import engine, Base, SessionLocal
    from backend.app.models import Plan, User
    from backend.app.auth import hash_password
    from backend.app.routers import (
        auth_router,
        subscription_router,
        device_router,
        entitlements_router,
        admin_router,
    )
except ImportError:
    from app.config import settings
    from app.database import engine, Base, SessionLocal
    from app.models import Plan, User
    from app.auth import hash_password
    from app.routers import (
        auth_router,
        subscription_router,
        device_router,
        entitlements_router,
        admin_router,
    )

Base.metadata.create_all(bind=engine)

app = FastAPI(title=settings.PROJECT_NAME, version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router.router)
app.include_router(subscription_router.router)
app.include_router(device_router.router)
app.include_router(entitlements_router.router)
app.include_router(admin_router.router)

@app.on_event("startup")
def seed_initial_data():
    db = SessionLocal()
    try:
        # Seed default plans if empty
        for plan_data in settings.DEFAULT_PLANS:
            p = db.query(Plan).filter(Plan.plan_id == plan_data["plan_id"]).first()
            if not p:
                db.add(Plan(**plan_data))

        # Seed default admin account if empty
        admin = db.query(User).filter(User.email == "admin@phonecam.app").first()
        if not admin:
            db.add(User(
                email="admin@phonecam.app",
                password_hash=hash_password("admin_secret_2025"),
                is_admin=True,
            ))

        db.commit()
    finally:
        db.close()

@app.get("/")
def health_check():
    return {"status": "ok", "app": settings.PROJECT_NAME, "version": "1.0.0"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
