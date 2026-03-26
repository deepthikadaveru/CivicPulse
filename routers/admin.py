from fastapi import APIRouter, Depends, HTTPException
from core.database import get_db
from core.auth import get_current_user
from core.utils import now_utc
from services.priority_engine import recalculate_all

router = APIRouter(prefix="/admin", tags=["Admin"])

SEED_DEPARTMENTS = [
    {
        "name": "Roads & Infrastructure", "code": "ROADS", "sla_days": 21,
        "categories": [
            {"name": "Pothole",           "slug": "pothole",          "icon": "pothole",   "weight": 1.5},
            {"name": "Road damage",       "slug": "road-damage",      "icon": "road",      "weight": 1.3},
            {"name": "Broken footpath",   "slug": "broken-footpath",  "icon": "footpath",  "weight": 1.0},
            {"name": "Missing road sign", "slug": "missing-sign",     "icon": "sign",      "weight": 0.8},
        ],
    },
    {
        "name": "Water & Drainage", "code": "WATER", "sla_days": 14,
        "categories": [
            {"name": "Drainage blocked", "slug": "drainage-blocked", "icon": "drain",   "weight": 1.6},
            {"name": "Sewage overflow",  "slug": "sewage-overflow",  "icon": "sewage",  "weight": 2.0},
            {"name": "Water leakage",    "slug": "water-leakage",    "icon": "pipe",    "weight": 1.2},
            {"name": "Flooding",         "slug": "flooding",         "icon": "flood",   "weight": 2.0},
        ],
    },
    {
        "name": "Electricity", "code": "ELEC", "sla_days": 7,
        "categories": [
            {"name": "Power line down",   "slug": "power-line-down", "icon": "powerline",   "weight": 2.5},
            {"name": "Street light out",  "slug": "streetlight-out", "icon": "streetlight", "weight": 1.0},
            {"name": "Transformer issue", "slug": "transformer",     "icon": "transformer", "weight": 2.0},
        ],
    },
    {
        "name": "Horticulture", "code": "HORT", "sla_days": 30,
        "categories": [
            {"name": "Overgrown tree", "slug": "overgrown-tree", "icon": "tree",        "weight": 1.1},
            {"name": "Fallen tree",    "slug": "fallen-tree",    "icon": "fallen-tree", "weight": 2.0},
            {"name": "Damaged park",   "slug": "damaged-park",   "icon": "park",        "weight": 0.9},
        ],
    },
    {
        "name": "Solid Waste Management", "code": "SWM", "sla_days": 3,
        "categories": [
            {"name": "Garbage not collected", "slug": "garbage-not-collected", "icon": "trash",   "weight": 1.2},
            {"name": "Illegal dumping",        "slug": "illegal-dumping",       "icon": "dumping", "weight": 1.4},
            {"name": "Overflowing bin",        "slug": "overflowing-bin",       "icon": "bin",     "weight": 1.0},
        ],
    },
    {
        "name": "Others", "code": "OTHER", "sla_days": 30,
        "categories": [
            {"name": "Stray animals",   "slug": "stray-animals",  "icon": "animal", "weight": 1.0},
            {"name": "Noise pollution", "slug": "noise-pollution", "icon": "noise",  "weight": 0.7},
            {"name": "Other issue",     "slug": "other",           "icon": "other",  "weight": 0.5},
        ],
    },
]


async def _require_super_admin(user=Depends(get_current_user)):
    if user.get("role") != "super_admin":
        raise HTTPException(status_code=403, detail="Super admin only")
    return user


@router.post("/seed/{city_id}", dependencies=[Depends(_require_super_admin)])
async def seed_city_data(city_id: str, db=Depends(get_db)):
    from core.utils import parse_object_id

    city = await db.cities.find_one({"_id": parse_object_id(city_id)})
    if not city:
        raise HTTPException(status_code=404, detail="City not found")

    created_depts = 0
    created_cats = 0

    for dept_data in SEED_DEPARTMENTS:
        # Find or create department
        existing_dept = await db.departments.find_one({
            "city_id": city_id,
            "code": dept_data["code"]
        })

        if existing_dept:
            dept_id = str(existing_dept["_id"])
        else:
            result = await db.departments.insert_one({
                "city_id": city_id,
                "name": dept_data["name"],
                "code": dept_data["code"],
                "sla_days": dept_data["sla_days"],
                "is_active": True,
                "created_at": now_utc(),
            })
            dept_id = str(result.inserted_id)
            created_depts += 1

        # Create categories for this department
        for cat in dept_data["categories"]:
            existing_cat = await db.issue_categories.find_one({
                "department_id": dept_id,
                "slug": cat["slug"],
            })
            if not existing_cat:
                await db.issue_categories.insert_one({
                    "department_id": dept_id,
                    "name": cat["name"],
                    "slug": cat["slug"],
                    "icon": cat["icon"],
                    "base_priority_weight": cat["weight"],
                    "description": "",
                    "is_active": True,
                    "created_at": now_utc(),
                })
                created_cats += 1

    return {
        "message": f"Seeded city: {city['name']}",
        "city_id": city_id,
        "departments_created": created_depts,
        "categories_created": created_cats,
    }


@router.post("/seed/{city_id}/force", dependencies=[Depends(_require_super_admin)])
async def force_reseed_city(city_id: str, db=Depends(get_db)):
    """
    Force delete all departments and categories for this city
    and recreate them from scratch. Use when seed shows 0 created.
    """
    from core.utils import parse_object_id

    city = await db.cities.find_one({"_id": parse_object_id(city_id)})
    if not city:
        raise HTTPException(status_code=404, detail="City not found")

    # Find all department IDs for this city
    dept_ids = []
    async for dept in db.departments.find({"city_id": city_id}):
        dept_ids.append(str(dept["_id"]))

    # Delete all categories linked to those departments
    cats_deleted = 0
    for dept_id in dept_ids:
        result = await db.issue_categories.delete_many({"department_id": dept_id})
        cats_deleted += result.deleted_count

    # Delete all departments for this city
    depts_result = await db.departments.delete_many({"city_id": city_id})

    # Re-run seed from scratch
    created_depts = 0
    created_cats = 0

    for dept_data in SEED_DEPARTMENTS:
        result = await db.departments.insert_one({
            "city_id": city_id,
            "name": dept_data["name"],
            "code": dept_data["code"],
            "sla_days": dept_data["sla_days"],
            "is_active": True,
            "created_at": now_utc(),
        })
        dept_id = str(result.inserted_id)
        created_depts += 1

        for cat in dept_data["categories"]:
            await db.issue_categories.insert_one({
                "department_id": dept_id,
                "name": cat["name"],
                "slug": cat["slug"],
                "icon": cat["icon"],
                "base_priority_weight": cat["weight"],
                "description": "",
                "is_active": True,
                "created_at": now_utc(),
            })
            created_cats += 1

    return {
        "message": f"Force reseeded city: {city['name']}",
        "city_id": city_id,
        "departments_deleted": depts_result.deleted_count,
        "categories_deleted": cats_deleted,
        "departments_created": created_depts,
        "categories_created": created_cats,
    }


@router.post("/recalculate-scores", dependencies=[Depends(_require_super_admin)])
async def trigger_recalculate(city_id: str = None, db=Depends(get_db)):
    count = await recalculate_all(db, city_id)
    return {"recalculated": count}


@router.post("/make-official", dependencies=[Depends(_require_super_admin)])
async def make_official(
    phone_number: str,
    role: str,
    department_id: str = None,
    db=Depends(get_db)
):
    valid_roles = ["dept_official", "city_admin", "super_admin"]
    if role not in valid_roles:
        raise HTTPException(
            status_code=400,
            detail=f"Role must be one of {valid_roles}"
        )

    user = await db.users.find_one({"phone_number": phone_number})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    updates = {"role": role}
    if department_id:
        updates["department_id"] = department_id

    await db.users.update_one(
        {"phone_number": phone_number},
        {"$set": updates}
    )
    return {"message": f"{phone_number} promoted to {role}"}
