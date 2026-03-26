import random
import string
from datetime import datetime, timedelta

OTP_EXPIRY_MINUTES = 10


def _generate_otp(length: int = 6) -> str:
    return "".join(random.choices(string.digits, k=length))


def _now():
    return datetime.utcnow()


async def send_otp(phone_number: str, db) -> dict:
    otp = _generate_otp()
    expires_at = _now() + timedelta(minutes=OTP_EXPIRY_MINUTES)

    await db.otp_sessions.update_one(
        {"phone_number": phone_number},
        {
            "$set": {
                "phone_number": phone_number,
                "otp": otp,
                "is_verified": False,
                "expires_at": expires_at,
                "created_at": _now(),
            }
        },
        upsert=True,
    )

    print(f"[DEV] OTP for {phone_number}: {otp}")

    return {
        "message": "OTP sent successfully",
        "otp": otp,
        "expires_in_minutes": OTP_EXPIRY_MINUTES,
        "dev_note": "OTP shown for testing only. Remove in production.",
    }


async def verify_otp(phone_number: str, otp: str, db) -> bool:
    session = await db.otp_sessions.find_one({"phone_number": phone_number})

    if not session:
        return False

    if session.get("otp") != otp:
        return False

    if session.get("expires_at") < _now():
        return False

    # Mark as verified (idempotent — safe to call twice for new users)
    await db.otp_sessions.update_one(
        {"phone_number": phone_number},
        {"$set": {"is_verified": True}},
    )
    return True