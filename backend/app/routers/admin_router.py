from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

try:
    from backend.app.database import get_db
    from backend.app.models import User, TrialClaim, Subscription, Device, utc_now
    from backend.app.schemas import AdminMetricsResponse
    from backend.app.auth import get_current_user
except ImportError:
    from app.database import get_db
    from app.models import User, TrialClaim, Subscription, Device, utc_now
    from app.schemas import AdminMetricsResponse
    from app.auth import get_current_user

router = APIRouter(prefix="/api/admin", tags=["Admin"])

@router.get("/metrics", response_model=AdminMetricsResponse)
def get_admin_metrics(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required.")

    now = utc_now()
    total_users = db.query(User).count()
    active_trials = db.query(TrialClaim).filter(TrialClaim.expires_at > now).count()
    active_subs = db.query(Subscription).filter(
        Subscription.status.in_(["active", "cancel_at_period_end"]),
        Subscription.current_period_end > now
    ).count()
    total_claims = db.query(TrialClaim).count()
    linked_devices = db.query(Device).count()

    conversion_rate = (active_subs / total_claims * 100.0) if total_claims > 0 else 0.0

    return AdminMetricsResponse(
        total_users=total_users,
        active_trials=active_trials,
        active_subscriptions=active_subs,
        linked_devices_count=linked_devices,
        conversion_rate_percent=round(conversion_rate, 2),
    )
