from fastapi import APIRouter, Depends, HTTPException
from core.database import get_db
from core.auth import create_access_token, get_current_user
from core.utils import serialize_doc, now_utc
from models.schemas import SendOTPRequest, VerifyOTPRequest, UpdateFCMTokenRequest
from services.otp_service import send_otp, verify_otp

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/send-otp")
async def send_otp_endpoint(body: SendOTPRequest, db=Depends(get_db)):
    """
    Step 1 of login: send OTP to phone number.
    In dev mode the OTP is returned in the response.
    """
    result = await send_otp(body.phone_number, db)
    return result


@router.post("/verify-otp")
async def verify_otp_endpoint(body: VerifyOTPRequest, db=Depends(get_db)):
    """
    Step 2 of login: verify OTP → returns JWT access token.
    If user doesn't exist yet, creates one (name required on first login).
    """
    is_valid = await verify_otp(body.phone_number, body.otp, db)
    if not is_valid:
        raise HTTPException(status_code=401, detail="Invalid or expired OTP")

    # Get or create user
    user = await db.users.find_one({"phone_number": body.phone_number})
    is_new = user is None

    if is_new:
        if not body.name or not body.name.strip():
            raise HTTPException(status_code=400, detail="Name is required for new users")
        user_doc = {
            "phone_number": body.phone_number,
            "name": body.name.strip(),
            "role": "citizen",
            "city_id": None,
            "department_id": None,
            "fcm_token": "",
            "is_active": True,
            "created_at": now_utc(),
        }
        result = await db.users.insert_one(user_doc)
        user = await db.users.find_one({"_id": result.inserted_id})

    user = serialize_doc(user)
    token = create_access_token(user["id"])

    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user["id"],
            "name": user["name"],
            "phone_number": user["phone_number"],
            "role": user["role"],
            "is_new": is_new,
        },
    }


@router.get("/me")
async def get_me(user=Depends(get_current_user)):
    """Returns the current logged-in user's profile."""
    return serialize_doc(user)


@router.post("/fcm-token")
async def update_fcm_token(
    body: UpdateFCMTokenRequest,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Save/update the device push notification token."""
    from bson import ObjectId
    await db.users.update_one(
        {"_id": ObjectId(user["id"])},
        {"$set": {"fcm_token": body.fcm_token}},
    )
    return {"status": "ok"}
