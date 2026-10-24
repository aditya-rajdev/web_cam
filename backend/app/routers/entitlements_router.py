from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

try:
    from backend.app.database import get_db
    from backend.app.config import settings
    from backend.app.models import User, TrialClaim, Subscription, Device, utc_now
    from backend.app.schemas import EntitlementsResponse, TrialStatusResponse, SubscriptionStatusResponse
    from backend.app.auth import get_current_user
except ImportError:
    from app.database import get_db
    from app.config import settings
    from app.models import User, TrialClaim, Subscription, Device, utc_now
    from app.schemas import EntitlementsResponse, TrialStatusResponse, SubscriptionStatusResponse
    from app.auth import get_current_user

router = APIRouter(prefix="/api/entitlements", tags=["Entitlements"])

@router.get("", response_model=EntitlementsResponse)
def get_entitlements(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    now = utc_now()

    # 1. Subscription Check
    sub = db.query(Subscription).filter(Subscription.user_id == user.id).first()
    has_sub = sub is not None and sub.status in ["active", "cancel_at_period_end"] and sub.current_period_end > now

    # 2. Trial Check
    trial = db.query(TrialClaim).filter(TrialClaim.user_id == user.id).first()
    has_trial = trial is not None and trial.expires_at > now
    remaining_seconds = max(0, int((trial.expires_at - now).total_seconds())) if trial and trial.expires_at > now else 0

    # 3. Device Count
    device_count = db.query(Device).filter(Device.user_id == user.id).count()

    if has_sub:
        has_pro_access = True
        reason = "active_subscription"
    elif has_trial:
        has_pro_access = True
        reason = "trial"
    else:
        has_pro_access = False
        reason = "expired"

    return EntitlementsResponse(
        user_id=user.id,
        has_pro_access=has_pro_access,
        access_reason=reason,
        trial_status=TrialStatusResponse(
            has_claimed_trial=trial is not None,
            trial_active=has_trial,
            started_at=trial.started_at if trial else None,
            expires_at=trial.expires_at if trial else None,
            remaining_seconds=remaining_seconds,
        ),
        subscription_status=SubscriptionStatusResponse(
            has_active_subscription=has_sub,
            plan_id=sub.plan_id if sub else None,
            plan_name=sub.plan.name if sub and sub.plan else (sub.plan_id if sub else None),
            status=sub.status if sub else None,
            current_period_end=sub.current_period_end if sub else None,
            cancel_at_period_end=sub.cancel_at_period_end if sub else False,
        ),
        linked_device_count=device_count,
        max_devices=settings.MAX_DEVICES_PER_ACCOUNT,
    )
