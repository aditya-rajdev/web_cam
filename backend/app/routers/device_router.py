from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

try:
    from backend.app.database import get_db
    from backend.app.config import settings
    from backend.app.models import User, Device, utc_now
    from backend.app.schemas import DeviceRegisterRequest, DeviceResponse
    from backend.app.auth import get_current_user
except ImportError:
    from app.database import get_db
    from app.config import settings
    from app.models import User, Device, utc_now
    from app.schemas import DeviceRegisterRequest, DeviceResponse
    from app.auth import get_current_user

router = APIRouter(prefix="/api/devices", tags=["Devices"])

@router.get("", response_model=List[DeviceResponse])
def get_devices(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    devices = db.query(Device).filter(Device.user_id == user.id).all()
    return [
        DeviceResponse(
            id=d.id,
            device_id=d.device_id,
            platform=d.platform,
            device_name=d.device_name,
            app_version=d.app_version,
            created_at=d.created_at,
            last_seen_at=d.last_seen_at,
        )
        for d in devices
    ]

@router.post("/register", response_model=DeviceResponse)
def register_device(
    req: DeviceRegisterRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    existing = db.query(Device).filter(
        Device.user_id == user.id,
        Device.device_id == req.device_id
    ).first()

    if existing:
        existing.device_name = req.device_name
        existing.platform = req.platform
        existing.app_version = req.app_version
        existing.last_seen_at = utc_now()
        db.commit()
        db.refresh(existing)
        return DeviceResponse(
            id=existing.id,
            device_id=existing.device_id,
            platform=existing.platform,
            device_name=existing.device_name,
            app_version=existing.app_version,
            created_at=existing.created_at,
            last_seen_at=existing.last_seen_at,
        )

    # Enforce strict 3-device limit
    current_count = db.query(Device).filter(Device.user_id == user.id).count()
    if current_count >= settings.MAX_DEVICES_PER_ACCOUNT:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Device limit reached. Maximum {settings.MAX_DEVICES_PER_ACCOUNT} linked devices allowed per account. Unlink an existing device first."
        )

    device = Device(
        user_id=user.id,
        device_id=req.device_id,
        platform=req.platform,
        device_name=req.device_name,
        app_version=req.app_version,
        created_at=utc_now(),
        last_seen_at=utc_now(),
    )
    db.add(device)
    db.commit()
    db.refresh(device)

    return DeviceResponse(
        id=device.id,
        device_id=device.device_id,
        platform=device.platform,
        device_name=device.device_name,
        app_version=device.app_version,
        created_at=device.created_at,
        last_seen_at=device.last_seen_at,
    )

@router.delete("/{device_id}")
def unlink_device(device_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = db.query(Device).filter(
        Device.user_id == user.id,
        Device.device_id == device_id
    ).first()

    if not device:
        raise HTTPException(status_code=404, detail="Device not found.")

    db.delete(device)
    db.commit()
    return {"status": "unlinked", "device_id": device_id}
