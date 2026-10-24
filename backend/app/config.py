import os

class Settings:
    PROJECT_NAME: str = "PhoneCam Subscription API"
    SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "phonecam_super_secret_production_key_2025")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30  # 30 days
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./phonecam.db")

    # Business Rules
    TRIAL_DURATION_HOURS: int = 72  # 3-Day Free Trial (72 hours exact)
    MAX_DEVICES_PER_ACCOUNT: int = 3  # 3-device limit across Android & Windows combined

    # Default Configurable Plans
    DEFAULT_PLANS = [
        {
            "plan_id": "plan_monthly",
            "name": "PhoneCam Pro Monthly",
            "billing_interval": "monthly",
            "price_cents": 499,
            "currency": "USD",
            "provider_price_id": "price_monthly_usd_499",
            "is_active": True,
        },
        {
            "plan_id": "plan_yearly",
            "name": "PhoneCam Pro Yearly (Save 33%)",
            "billing_interval": "yearly",
            "price_cents": 3999,
            "currency": "USD",
            "provider_price_id": "price_yearly_usd_3999",
            "is_active": True,
        },
    ]

settings = Settings()
