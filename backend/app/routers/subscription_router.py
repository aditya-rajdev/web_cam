from datetime import datetime, timedelta, timezone
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Header, Request
from sqlalchemy.orm import Session

try:
    from backend.app.database import get_db
    from backend.app.config import settings
    from backend.app.models import User, Plan, TrialClaim, Subscription, WebhookEvent, utc_now
    from backend.app.schemas import (
        PlanResponse,
        TrialStatusResponse,
        SubscriptionStatusResponse,
        CheckoutRequest,
        CheckoutResponse,
    )
    from backend.app.auth import get_current_user
except ImportError:
    from app.database import get_db
    from app.config import settings
    from app.models import User, Plan, TrialClaim, Subscription, WebhookEvent, utc_now
    from app.schemas import (
        PlanResponse,
        TrialStatusResponse,
        SubscriptionStatusResponse,
        CheckoutRequest,
        CheckoutResponse,
    )
    from app.auth import get_current_user

router = APIRouter(prefix="/api/subscription", tags=["Subscription"])

@router.get("/plans", response_model=List[PlanResponse])
def get_plans(db: Session = Depends(get_db)):
    plans = db.query(Plan).filter(Plan.is_active == True).all()
    return [
        PlanResponse(
            plan_id=p.plan_id,
            name=p.name,
            billing_interval=p.billing_interval,
            price_cents=p.price_cents,
            currency=p.currency,
            is_active=p.is_active,
        )
        for p in plans
    ]

@router.post("/trial/start", response_model=TrialStatusResponse)
def start_trial(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    existing_claim = db.query(TrialClaim).filter(TrialClaim.user_id == user.id).first()
    if existing_claim:
        now = utc_now()
        rem = max(0, int((existing_claim.expires_at - now).total_seconds())) if existing_claim.expires_at > now else 0
        return TrialStatusResponse(
            has_claimed_trial=True,
            trial_active=rem > 0,
            started_at=existing_claim.started_at,
            expires_at=existing_claim.expires_at,
            remaining_seconds=rem,
        )

    now = utc_now()
    expires_at = now + timedelta(hours=settings.TRIAL_DURATION_HOURS)

    trial = TrialClaim(
        user_id=user.id,
        started_at=now,
        expires_at=expires_at,
    )
    db.add(trial)
    try:
        db.commit()
        db.refresh(trial)
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Free trial already claimed for this account."
        )

    return TrialStatusResponse(
        has_claimed_trial=True,
        trial_active=True,
        started_at=trial.started_at,
        expires_at=trial.expires_at,
        remaining_seconds=settings.TRIAL_DURATION_HOURS * 3600,
    )

@router.get("/status", response_model=SubscriptionStatusResponse)
def get_subscription_status(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    sub = db.query(Subscription).filter(Subscription.user_id == user.id).first()
    if not sub:
        return SubscriptionStatusResponse(has_active_subscription=False)

    now = utc_now()
    is_active = sub.status in ["active", "cancel_at_period_end"] and sub.current_period_end > now

    return SubscriptionStatusResponse(
        has_active_subscription=is_active,
        plan_id=sub.plan_id,
        plan_name=sub.plan.name if sub.plan else sub.plan_id,
        status=sub.status,
        current_period_end=sub.current_period_end,
        cancel_at_period_end=sub.cancel_at_period_end,
    )

@router.post("/checkout", response_model=CheckoutResponse)
def create_checkout_session(req: CheckoutRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    plan = db.query(Plan).filter(Plan.plan_id == req.plan_id, Plan.is_active == True).first()
    if not plan:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan not found.")

    session_id = f"chk_sess_{user.id}_{plan.plan_id}_{int(utc_now().timestamp())}"
    checkout_url = f"https://checkout.phonecam.app/pay?session_id={session_id}&user_id={user.id}&plan_id={plan.plan_id}"

    return CheckoutResponse(checkout_url=checkout_url, session_id=session_id)

@router.post("/webhook")
async def handle_payment_webhook(request: Request, db: Session = Depends(get_db)):
    payload = await request.json()
    event_id = payload.get("event_id")
    event_type = payload.get("type")

    if not event_id:
        raise HTTPException(status_code=400, detail="Missing event_id")

    existing_evt = db.query(WebhookEvent).filter(WebhookEvent.provider_event_id == event_id).first()
    if existing_evt:
        return {"status": "already_processed"}

    db.add(WebhookEvent(provider_event_id=event_id))

    if event_type == "subscription.created" or event_type == "payment.succeeded":
        user_id = payload.get("user_id")
        plan_id = payload.get("plan_id")
        duration_days = 365 if "yearly" in plan_id else 30

        sub = db.query(Subscription).filter(Subscription.user_id == user_id).first()
        now = utc_now()
        period_end = now + timedelta(days=duration_days)

        if sub:
            sub.plan_id = plan_id
            sub.status = "active"
            sub.current_period_start = now
            sub.current_period_end = period_end
            sub.cancel_at_period_end = False
            sub.updated_at = now
        else:
            sub = Subscription(
                user_id=user_id,
                plan_id=plan_id,
                status="active",
                current_period_start=now,
                current_period_end=period_end,
                payment_provider="stripe",
                provider_subscription_id=payload.get("subscription_id", "sub_test"),
            )
            db.add(sub)

    db.commit()
    return {"status": "success"}

@router.post("/cancel", response_model=SubscriptionStatusResponse)
def cancel_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    sub = db.query(Subscription).filter(Subscription.user_id == user.id).first()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found.")

    sub.cancel_at_period_end = True
    sub.status = "cancel_at_period_end"
    db.commit()
    db.refresh(sub)

    return SubscriptionStatusResponse(
        has_active_subscription=sub.current_period_end > utc_now(),
        plan_id=sub.plan_id,
        plan_name=sub.plan.name if sub.plan else sub.plan_id,
        status=sub.status,
        current_period_end=sub.current_period_end,
        cancel_at_period_end=True,
    )
