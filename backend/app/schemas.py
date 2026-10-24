from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, EmailStr

class UserRegisterRequest(BaseModel):
    email: EmailStr
    password: str

class UserLoginRequest(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    email: str

class UserProfileResponse(BaseModel):
    id: int
    email: str
    is_admin: bool
    created_at: datetime

class PlanResponse(BaseModel):
    plan_id: str
    name: str
    billing_interval: str
    price_cents: int
    currency: str
    is_active: bool

class TrialStatusResponse(BaseModel):
    has_claimed_trial: bool
    trial_active: bool
    started_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    remaining_seconds: int = 0

class SubscriptionStatusResponse(BaseModel):
    has_active_subscription: bool
    plan_id: Optional[str] = None
    plan_name: Optional[str] = None
    status: Optional[str] = None
    current_period_end: Optional[datetime] = None
    cancel_at_period_end: bool = False

class EntitlementsResponse(BaseModel):
    user_id: int
    has_pro_access: bool
    access_reason: str  # "trial", "active_subscription", or "expired"
    trial_status: TrialStatusResponse
    subscription_status: SubscriptionStatusResponse
    linked_device_count: int
    max_devices: int = 3

class CheckoutRequest(BaseModel):
    plan_id: str

class CheckoutResponse(BaseModel):
    checkout_url: str
    session_id: str

class DeviceRegisterRequest(BaseModel):
    device_id: str
    platform: str  # "android" or "windows"
    device_name: str
    app_version: str = "1.0.0"

class DeviceResponse(BaseModel):
    id: int
    device_id: str
    platform: str
    device_name: str
    app_version: str
    created_at: datetime
    last_seen_at: datetime

class AdminMetricsResponse(BaseModel):
    total_users: int
    active_trials: int
    active_subscriptions: int
    linked_devices_count: int
    conversion_rate_percent: float
