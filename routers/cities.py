from fastapi import APIRouter, Depends, HTTPException
from core.database import get_db
from core.auth import get_current_official
from core.utils import serialize_doc, now_utc
from models.schemas import CityCreateRequest

router = APIRouter(prefix="/cities", tags=["Cities"])


@router.get("/")
async def list_cities(db=Depends(get_db)):
    cities = []
    async for doc in db.cities.find({"is_active": True}):
        cities.append(serialize_doc(doc))
    return cities


@router.post("/", dependencies=[Depends(get_current_official)])
async def create_city(body: CityCreateRequest, db=Depends(get_db)):
    existing = await db.cities.find_one({"name": body.name, "state": body.state})
    if existing:
        raise HTTPException(status_code=400, detail="City already exists")

    doc = {**body.model_dump(), "is_active": True, "created_at": now_utc()}
    result = await db.cities.insert_one(doc)
    city = await db.cities.find_one({"_id": result.inserted_id})
    return serialize_doc(city)
