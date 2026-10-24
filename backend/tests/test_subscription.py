import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from backend.app.database import Base, get_db
from backend.main import app

TEST_DATABASE_URL = "sqlite:///./test_phonecam.db"
engine = create_engine(TEST_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(autouse=True)
def setup_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)

client = TestClient(app)

def test_full_subscription_lifecycle():
    # 1. Register User
    reg_resp = client.post("/api/auth/register", json={
        "email": "user1@example.com",
        "password": "Password123!"
    })
    assert reg_resp.status_code == 200
    token = reg_resp.json()["access_token"]
    user_id = reg_resp.json()["user_id"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Check Entitlements (Before Trial)
    ent_resp = client.get("/api/entitlements", headers=headers)
    assert ent_resp.status_code == 200
    assert ent_resp.json()["has_pro_access"] is False
    assert ent_resp.json()["access_reason"] == "expired"

    # 3. Claim 3-Day Free Trial (72 hours)
    trial_resp = client.post("/api/subscription/trial/start", headers=headers)
    assert trial_resp.status_code == 200
    assert trial_resp.json()["trial_active"] is True
    assert trial_resp.json()["remaining_seconds"] == 72 * 3600

    # Check Entitlements (During Trial)
    ent_resp2 = client.get("/api/entitlements", headers=headers)
    assert ent_resp2.status_code == 200
    assert ent_resp2.json()["has_pro_access"] is True
    assert ent_resp2.json()["access_reason"] == "trial"

    # Repeat trial claim returns existing claim without extension
    repeat_trial = client.post("/api/subscription/trial/start", headers=headers)
    assert repeat_trial.status_code == 200
    assert repeat_trial.json()["has_claimed_trial"] is True

    # 4. Test 3-Device Limit
    dev1 = client.post("/api/devices/register", json={"device_id": "d1", "platform": "windows", "device_name": "PC 1"}, headers=headers)
    assert dev1.status_code == 200

    dev2 = client.post("/api/devices/register", json={"device_id": "d2", "platform": "android", "device_name": "Phone 1"}, headers=headers)
    assert dev2.status_code == 200

    dev3 = client.post("/api/devices/register", json={"device_id": "d3", "platform": "android", "device_name": "Tablet 1"}, headers=headers)
    assert dev3.status_code == 200

    # 4th Device Rejection
    dev4 = client.post("/api/devices/register", json={"device_id": "d4", "platform": "windows", "device_name": "PC 2"}, headers=headers)
    assert dev4.status_code == 403
    assert "Device limit reached" in dev4.json()["detail"]

    # Unlink Device 1
    unl = client.delete("/api/devices/d1", headers=headers)
    assert unl.status_code == 200

    # Now 4th Device (now 3rd active device) succeeds
    dev4_retry = client.post("/api/devices/register", json={"device_id": "d4", "platform": "windows", "device_name": "PC 2"}, headers=headers)
    assert dev4_retry.status_code == 200

    # 5. Simulate Payment Webhook Activation
    wh_resp = client.post("/api/subscription/webhook", json={
        "event_id": "evt_test_1001",
        "type": "subscription.created",
        "user_id": user_id,
        "plan_id": "plan_yearly",
        "subscription_id": "sub_yearly_12345"
    })
    assert wh_resp.status_code == 200

    # Verify Active Subscription Entitlements
    ent_resp3 = client.get("/api/entitlements", headers=headers)
    assert ent_resp3.status_code == 200
    assert ent_resp3.json()["has_pro_access"] is True
    assert ent_resp3.json()["access_reason"] == "active_subscription"
