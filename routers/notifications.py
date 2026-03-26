from fastapi import APIRouter, Depends
from core.database import get_db
from core.auth import get_current_user
from core.utils import serialize_doc

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get("/")
async def list_notifications(user=Depends(get_current_user), db=Depends(get_db)):
    user_id = str(user["_id"])
    notifs = []
    async for doc in db.notifications.find(
        {"user_id": user_id}
    ).sort("created_at", -1).limit(50):
        notifs.append(serialize_doc(doc))
    return notifs


@router.post("/mark-read")
async def mark_all_read(user=Depends(get_current_user), db=Depends(get_db)):
    user_id = str(user["_id"])
    await db.notifications.update_many(
        {"user_id": user_id, "is_read": False},
        {"$set": {"is_read": True}}
    )
    return {"status": "ok"}
