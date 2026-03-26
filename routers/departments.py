from fastapi import APIRouter, Depends, HTTPException, Query
from core.database import get_db
from core.auth import get_current_official
from core.utils import serialize_doc, now_utc
from models.schemas import DepartmentCreateRequest, CategoryCreateRequest

router = APIRouter(prefix="/departments", tags=["Departments"])


@router.get("/")
async def list_departments(city_id: str = Query(...), db=Depends(get_db)):
    depts = []
    async for doc in db.departments.find({"city_id": city_id, "is_active": True}):
        depts.append(serialize_doc(doc))
    return depts


@router.get("/categories")
async def list_categories(city_id: str = Query(...), db=Depends(get_db)):
    # Step 1: get all departments for this city
    dept_map = {}
    async for dept in db.departments.find({"city_id": city_id, "is_active": True}):
        dept_id = str(dept["_id"])
        dept_map[dept_id] = {
            "department_name": dept["name"],
            "department_code": dept["code"],
        }

    if not dept_map:
        return []

    # Step 2: get all categories where department_id matches any of those dept IDs
    categories = []
    async for cat in db.issue_categories.find({
        "department_id": {"$in": list(dept_map.keys())},
        "is_active": True,
    }):
        dept_info = dept_map.get(str(cat["department_id"]), {})
        from core.utils import serialize_doc
        cat_doc = serialize_doc(cat)
        cat_doc["department_name"] = dept_info.get("department_name", "")
        cat_doc["department_code"] = dept_info.get("department_code", "")
        categories.append(cat_doc)

    return categories


@router.post("/", dependencies=[Depends(get_current_official)])
async def create_department(body: DepartmentCreateRequest, db=Depends(get_db)):
    existing = await db.departments.find_one({"city_id": body.city_id, "code": body.code})
    if existing:
        raise HTTPException(status_code=400, detail="Department code already exists in this city")
    doc = {**body.model_dump(), "is_active": True, "created_at": now_utc()}
    result = await db.departments.insert_one(doc)
    dept = await db.departments.find_one({"_id": result.inserted_id})
    return serialize_doc(dept)


@router.post("/categories", dependencies=[Depends(get_current_official)])
async def create_category(body: CategoryCreateRequest, db=Depends(get_db)):
    existing = await db.issue_categories.find_one({
        "department_id": body.department_id, "slug": body.slug
    })
    if existing:
        raise HTTPException(status_code=400, detail="Category slug already exists in this department")
    doc = {**body.model_dump(), "is_active": True, "created_at": now_utc()}
    result = await db.issue_categories.insert_one(doc)
    cat = await db.issue_categories.find_one({"_id": result.inserted_id})
    return serialize_doc(cat)
