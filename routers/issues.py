from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Form
from typing import Optional
from bson import ObjectId
from core.database import get_db
from core.auth import get_current_user, get_current_official, get_optional_user
from core.utils import serialize_doc, now_utc, parse_object_id
from models.schemas import (
    IssueStatusUpdateRequest, ConfirmCategoryRequest, AddCommentRequest
)
from services.priority_engine import recalculate_issue, compute_priority_score
from services.duplicate_detector import find_nearby_issues
from services.media_service import save_media, get_media_url
from services.classifier import classify_issue

router = APIRouter(prefix="/issues", tags=["Issues"])


def _serialize_issue(doc: dict) -> dict:
    doc = serialize_doc(doc)
    # Flatten GeoJSON location to lat/lng for convenience
    if doc.get("location") and doc["location"].get("coordinates"):
        coords = doc["location"]["coordinates"]
        doc["longitude"] = coords[0]
        doc["latitude"] = coords[1]
    return doc


# ─── Report a new issue ───────────────────────────────────────────────────────

@router.post("/")
async def create_issue(
    title: str = Form(...),
    description: str = Form(""),
    latitude: float = Form(...),
    longitude: float = Form(...),
    address: str = Form(""),
    road_type: str = Form("none"),
    category_id: Optional[str] = Form(None),
    city_id: str = Form(...),
    photo: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    # Validate city
    city = await db.cities.find_one({"_id": parse_object_id(city_id)})
    if not city:
        raise HTTPException(status_code=404, detail="City not found")

    # Resolve category and department
    category_doc = None
    department_doc = None
    category_base_weight = 1.0

    if category_id:
        category_doc = await db.issue_categories.find_one({"_id": parse_object_id(category_id)})
        if category_doc:
            department_doc = await db.departments.find_one(
                {"_id": ObjectId(category_doc["department_id"])}
            )
            category_base_weight = category_doc.get("base_priority_weight", 1.0)

    # Build issue document
    issue_doc = {
        "title": title,
        "description": description,
        "location": {"type": "Point", "coordinates": [longitude, latitude]},
        "address": address,
        "road_type": road_type,
        "city_id": city_id,
        "ward_id": None,
        "reporter_id": str(user["_id"]),
        "reporter_name": user.get("name", ""),
        "category_id": category_id,
        "category_name": category_doc["name"] if category_doc else None,
        "category_base_weight": category_base_weight,
        "department_id": str(department_doc["_id"]) if department_doc else None,
        "department_name": department_doc["name"] if department_doc else None,
        "status": "pending",
        "severity": "low",
        "priority_score": 0.0,
        "report_count": 1,
        "upvote_count": 0,
        "is_escalated": False,
        "escalated_at": None,
        "ai_suggested_category_id": None,
        "ai_suggested_category_name": None,
        "ai_confidence": 0.0,
        "ai_reasoning": None,
        "media": [],
        "created_at": now_utc(),
        "updated_at": now_utc(),
        "resolved_at": None,
    }

    # Compute initial priority
    score_updates = compute_priority_score(issue_doc)
    issue_doc.update(score_updates)

    result = await db.issues.insert_one(issue_doc)
    issue_id = str(result.inserted_id)

    # Save photo
    photo_path = None
    if photo and photo.filename:
        media_info = await save_media(photo)
        photo_path = media_info["file_path"]
        issue_doc["media"].append({
            "media_type": "photo",
            "file_path": media_info["file_path"],
            "thumbnail_path": media_info["thumbnail_path"],
            "file_url": get_media_url(media_info["file_path"]),
            "thumbnail_url": get_media_url(media_info["thumbnail_path"]),
            "uploaded_at": now_utc(),
        })
        await db.issues.update_one(
            {"_id": result.inserted_id},
            {"$set": {"media": issue_doc["media"]}}
        )

    # Save video
    if video and video.filename:
        video_info = await save_media(video)
        issue_doc["media"].append({
            "media_type": "video",
            "file_path": video_info["file_path"],
            "file_url": get_media_url(video_info["file_path"]),
            "thumbnail_url": None,
            "uploaded_at": now_utc(),
        })
        await db.issues.update_one(
            {"_id": result.inserted_id},
            {"$set": {"media": issue_doc["media"]}}
        )

    # AI classification (if photo and no category selected yet)
    if photo_path and not category_id:
        categories = []
        async for c in db.issue_categories.find({"is_active": True}):
            dept = await db.departments.find_one({"_id": ObjectId(c["department_id"])})
            categories.append({
                "slug": c["slug"],
                "name": c["name"],
                "department_name": dept["name"] if dept else "",
            })
        ai_result = await classify_issue(photo_path, description, categories)
        ai_updates = {
            "ai_reasoning": ai_result.get("reasoning"),
            "ai_confidence": ai_result.get("confidence", 0.0),
        }
        if ai_result.get("category_slug"):
            ai_cat = await db.issue_categories.find_one({"slug": ai_result["category_slug"]})
            if ai_cat:
                ai_updates["ai_suggested_category_id"] = str(ai_cat["_id"])
                ai_updates["ai_suggested_category_name"] = ai_cat["name"]
        await db.issues.update_one({"_id": result.inserted_id}, {"$set": ai_updates})

    # Initial status log
    await db.issue_status_logs.insert_one({
        "issue_id": issue_id,
        "changed_by_id": str(user["_id"]),
        "changed_by_name": user.get("name", ""),
        "from_status": "",
        "to_status": "pending",
        "note": "Issue reported by citizen",
        "created_at": now_utc(),
    })

    issue = await db.issues.find_one({"_id": result.inserted_id})
    return _serialize_issue(issue)


# ─── List issues ──────────────────────────────────────────────────────────────

@router.get("/")
async def list_issues(
    city_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    severity: Optional[str] = Query(None),
    department_id: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    db=Depends(get_db),
):
    query = {}
    if city_id:
        query["city_id"] = city_id
    if status:
        query["status"] = status
    if severity:
        query["severity"] = severity
    if department_id:
        query["department_id"] = department_id

    skip = (page - 1) * limit
    total = await db.issues.count_documents(query)
    issues = []
    async for doc in db.issues.find(query).sort("priority_score", -1).skip(skip).limit(limit):
        issues.append(_serialize_issue(doc))

    return {"total": total, "page": page, "limit": limit, "issues": issues}


# ─── Map pins ─────────────────────────────────────────────────────────────────

@router.get("/map-pins")
async def map_pins(
    city_id: Optional[str] = Query(None),
    status_filter: str = Query("all", alias="status"),
    min_lng: float = Query(...),
    min_lat: float = Query(...),
    max_lng: float = Query(...),
    max_lat: float = Query(...),
    db=Depends(get_db),
):
    """
    Returns issues within the map viewport bounding box.
    Used by the public map — no auth required.
    """
    query = {
        "location": {
            "$geoWithin": {
                "$box": [[min_lng, min_lat], [max_lng, max_lat]]
            }
        }
    }
    if city_id:
        query["city_id"] = city_id
    if status_filter == "active":
        query["status"] = {"$nin": ["resolved", "rejected"]}
    elif status_filter == "resolved":
        query["status"] = "resolved"

    pins = []
    async for doc in db.issues.find(query).limit(500):
        coords = doc.get("location", {}).get("coordinates", [0, 0])
        pins.append({
            "id": str(doc["_id"]),
            "title": doc.get("title"),
            "status": doc.get("status"),
            "severity": doc.get("severity"),
            "latitude": coords[1],
            "longitude": coords[0],
            "category_name": doc.get("category_name"),
            "department_name": doc.get("department_name"),
            "report_count": doc.get("report_count", 1),
            "upvote_count": doc.get("upvote_count", 0),
            "days_open": doc.get("days_open", 0),
            "is_escalated": doc.get("is_escalated", False),
            "thumbnail_url": (doc.get("media") or [{}])[0].get("thumbnail_url") if doc.get("media") else None,
            "created_at": doc.get("created_at").isoformat() if doc.get("created_at") else None,
        })
    return pins


# ─── Check nearby duplicates ──────────────────────────────────────────────────

@router.get("/check-nearby")
async def check_nearby(
    latitude: float = Query(...),
    longitude: float = Query(...),
    category_id: str = Query(...),
    city_id: str = Query(...),
    db=Depends(get_db),
):
    nearby = await find_nearby_issues(latitude, longitude, category_id, city_id, db)
    return {
        "count": len(nearby),
        "nearby_issues": [_serialize_issue(i) for i in nearby],
    }


# ─── Single issue detail ──────────────────────────────────────────────────────

@router.get("/{issue_id}")
async def get_issue(
    issue_id: str,
    user=Depends(get_optional_user),
    db=Depends(get_db),
):
    issue = await db.issues.find_one({"_id": parse_object_id(issue_id)})
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    result = _serialize_issue(issue)

    # Attach status logs
    logs = []
    async for log in db.issue_status_logs.find(
        {"issue_id": issue_id}
    ).sort("created_at", 1):
        logs.append(serialize_doc(log))
    result["status_logs"] = logs

    # Attach comments
    comments = []
    async for c in db.issue_comments.find(
        {"issue_id": issue_id}
    ).sort("created_at", 1):
        comments.append(serialize_doc(c))
    result["comments"] = comments

    # Has current user voted?
    result["has_voted"] = False
    if user:
        vote = await db.issue_votes.find_one({
            "issue_id": issue_id,
            "user_id": str(user["_id"])
        })
        result["has_voted"] = vote is not None

    return result


# ─── Upvote ───────────────────────────────────────────────────────────────────

@router.post("/{issue_id}/upvote")
async def toggle_upvote(
    issue_id: str,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    issue = await db.issues.find_one({"_id": parse_object_id(issue_id)})
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    user_id = str(user["_id"])
    existing_vote = await db.issue_votes.find_one({"issue_id": issue_id, "user_id": user_id})

    if existing_vote:
        await db.issue_votes.delete_one({"issue_id": issue_id, "user_id": user_id})
        new_count = max(0, issue.get("upvote_count", 0) - 1)
        await db.issues.update_one(
            {"_id": parse_object_id(issue_id)},
            {"$set": {"upvote_count": new_count, "updated_at": now_utc()}}
        )
        await recalculate_issue(issue_id, db)
        return {"status": "removed", "upvote_count": new_count}

    await db.issue_votes.insert_one({
        "issue_id": issue_id,
        "user_id": user_id,
        "created_at": now_utc(),
    })
    new_count = issue.get("upvote_count", 0) + 1
    await db.issues.update_one(
        {"_id": parse_object_id(issue_id)},
        {"$set": {"upvote_count": new_count, "updated_at": now_utc()}}
    )
    await recalculate_issue(issue_id, db)
    return {"status": "added", "upvote_count": new_count}


# ─── Confirm / override AI category ──────────────────────────────────────────

@router.post("/{issue_id}/confirm-category")
async def confirm_category(
    issue_id: str,
    body: ConfirmCategoryRequest,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    issue = await db.issues.find_one({"_id": parse_object_id(issue_id)})
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    if str(issue["reporter_id"]) != str(user["_id"]):
        raise HTTPException(status_code=403, detail="Not your report")

    cat = await db.issue_categories.find_one({"_id": parse_object_id(body.category_id)})
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    dept = await db.departments.find_one({"_id": ObjectId(cat["department_id"])})

    await db.issues.update_one(
        {"_id": parse_object_id(issue_id)},
        {"$set": {
            "category_id": body.category_id,
            "category_name": cat["name"],
            "category_base_weight": cat.get("base_priority_weight", 1.0),
            "department_id": str(dept["_id"]) if dept else None,
            "department_name": dept["name"] if dept else None,
            "status": "assigned",
            "updated_at": now_utc(),
        }}
    )
    await db.issue_status_logs.insert_one({
        "issue_id": issue_id,
        "changed_by_id": str(user["_id"]),
        "changed_by_name": user.get("name", ""),
        "from_status": issue["status"],
        "to_status": "assigned",
        "note": f"Routed to {dept['name'] if dept else 'Unknown'} by reporter",
        "created_at": now_utc(),
    })
    await recalculate_issue(issue_id, db)
    return {"category": cat["name"], "department": dept["name"] if dept else None}


# ─── Update status (officials only) ──────────────────────────────────────────

@router.post("/{issue_id}/update-status")
async def update_status(
    issue_id: str,
    body: IssueStatusUpdateRequest,
    user=Depends(get_current_official),
    db=Depends(get_db),
):
    issue = await db.issues.find_one({"_id": parse_object_id(issue_id)})
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    updates = {
        "status": body.status.value,
        "updated_at": now_utc(),
    }
    if body.status.value == "resolved":
        updates["resolved_at"] = now_utc()

    await db.issues.update_one({"_id": parse_object_id(issue_id)}, {"$set": updates})
    await db.issue_status_logs.insert_one({
        "issue_id": issue_id,
        "changed_by_id": str(user["_id"]),
        "changed_by_name": user.get("name", ""),
        "from_status": issue["status"],
        "to_status": body.status.value,
        "note": body.note,
        "created_at": now_utc(),
    })

    return {"status": body.status.value}


# ─── Add comment ─────────────────────────────────────────────────────────────

@router.post("/{issue_id}/comment")
async def add_comment(
    issue_id: str,
    body: AddCommentRequest,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    issue = await db.issues.find_one({"_id": parse_object_id(issue_id)})
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    role = user.get("role", "citizen")
    comment = {
        "issue_id": issue_id,
        "author_id": str(user["_id"]),
        "author_name": user.get("name", ""),
        "is_official": role in ["dept_official", "city_admin", "super_admin"],
        "text": body.text,
        "created_at": now_utc(),
    }
    result = await db.issue_comments.insert_one(comment)
    comment["id"] = str(result.inserted_id)
    comment.pop("_id", None)
    return comment
