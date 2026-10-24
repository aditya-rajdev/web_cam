from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship

try:
    from backend.app.database import Base
except ImportError:
    from app.database import Base

def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    is_admin = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utc_now)

    trial_claim = relationship("TrialClaim", back_populates="user", uselist=False)
    subscription = relationship("Subscription", back_populates="user", uselist=False)
    devices = relationship("Device", back_populates="user")


class TrialClaim(Base):
    __tablename__ = "trial_claims"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    started_at = Column(DateTime, default=utc_now, nullable=False)
    expires_at = Column(DateTime, nullable=False)

    user = relationship("User", back_populates="trial_claim")


class Plan(Base):
    __tablename__ = "plans"

    plan_id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    billing_interval = Column(String, nullable=False)  # "monthly" or "yearly"
    price_cents = Column(Integer, nullable=False)
    currency = Column(String, default="USD")
    provider_price_id = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)


class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    plan_id = Column(String, ForeignKey("plans.plan_id"), nullable=False)
    status = Column(String, default="active")  # active, cancel_at_period_end, past_due, expired, refunded
    current_period_start = Column(DateTime, default=utc_now)
    current_period_end = Column(DateTime, nullable=False)
    cancel_at_period_end = Column(Boolean, default=False)
    payment_provider = Column(String, default="stripe")  # stripe, google_play, custom
    provider_subscription_id = Column(String, nullable=True)
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)

    user = relationship("User", back_populates="subscription")
    plan = relationship("Plan")


class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id = Column(String, nullable=False)
    platform = Column(String, nullable=False)  # "android" or "windows"
    device_name = Column(String, nullable=False)
    app_version = Column(String, default="1.0.0")
    created_at = Column(DateTime, default=utc_now)
    last_seen_at = Column(DateTime, default=utc_now, onupdate=utc_now)

    user = relationship("User", back_populates="devices")

    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_user_device"),
    )


class WebhookEvent(Base):
    __tablename__ = "webhook_events"

    id = Column(Integer, primary_key=True, index=True)
    provider_event_id = Column(String, unique=True, index=True, nullable=False)
    processed_at = Column(DateTime, default=utc_now)
