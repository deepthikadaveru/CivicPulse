"""
Priority engine — computes score for every issue.
Called on: new report, new upvote, nightly recalculation.
"""
from datetime import datetime, timezone
from core.config import get_settings

settings = get_settings()

ROAD_WEIGHTS = {
    "highway": 3.0,
    "main_road": 2.0,
    "lane": 1.0,
    "none": 0.0,
}

SEVERITY_THRESHOLDS = [
    (40, "critical"),
    (20, "high"),
    (8,  "moderate"),
    (0,  "low"),
]


def compute_priority_score(issue: dict, ward: dict = None) -> dict:
    """
    Computes priority_score and severity for an issue document.
    Returns updated fields as a dict — caller saves to DB.
    """
    created_at = issue.get("created_at", datetime.now(timezone.utc))
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    days_open = (datetime.now(timezone.utc) - created_at).days

    report_count = issue.get("report_count", 1)
    upvote_count = issue.get("upvote_count", 0)
    road_type    = issue.get("road_type", "none")
    category_weight = issue.get("category_base_weight", 1.0)

    population_density = ward.get("population_density", 0) if ward else 0
    near_sensitive     = (ward.get("has_school") or ward.get("has_hospital")) if ward else False

    base_score = (
        (report_count  * settings.WEIGHT_REPORT_COUNT)
        + (upvote_count  * settings.WEIGHT_UPVOTES)
        + (min(population_density / 1000, 10) * settings.WEIGHT_POPULATION_DENSITY)
        + (ROAD_WEIGHTS.get(road_type, 0) * settings.WEIGHT_ROAD_TYPE)
        + ((1.0 if near_sensitive else 0.0) * settings.WEIGHT_SENSITIVE_LOCATION)
    ) * category_weight

    # Starvation floor: low-report issues gain score per day so they're never buried
    if report_count < 3:
        floor = days_open * settings.STARVATION_FLOOR_PER_DAY
        base_score = max(base_score, floor)

    score = round(base_score, 2)

    # Derive severity
    severity = "low"
    for threshold, label in SEVERITY_THRESHOLDS:
        if score >= threshold:
            severity = label
            break

    # Check escalation
    is_escalated = (
        score >= settings.ESCALATION_SCORE_THRESHOLD
        or days_open >= settings.ESCALATION_DAYS_THRESHOLD
    )

    return {
        "priority_score": score,
        "severity": severity,
        "days_open": days_open,
        "is_escalated": is_escalated,
    }


async def recalculate_issue(issue_id: str, db):
    """Recalculate and save score for a single issue."""
    from bson import ObjectId
    from core.utils import now_utc

    issue = await db.issues.find_one({"_id": ObjectId(issue_id)})
    if not issue:
        return

    ward = None
    if issue.get("ward_id"):
        ward = await db.wards.find_one({"_id": ObjectId(issue["ward_id"])})

    updates = compute_priority_score(issue, ward)

    if updates["is_escalated"] and not issue.get("is_escalated"):
        updates["escalated_at"] = now_utc()

    await db.issues.update_one(
        {"_id": ObjectId(issue_id)},
        {"$set": updates}
    )
    return updates


async def recalculate_all(db, city_id: str = None):
    """Nightly job: recalculate all open issues."""
    from bson import ObjectId
    from core.utils import now_utc

    query = {"status": {"$nin": ["resolved", "rejected"]}}
    if city_id:
        query["city_id"] = city_id

    count = 0
    async for issue in db.issues.find(query):
        ward = None
        if issue.get("ward_id"):
            ward = await db.wards.find_one({"_id": issue["ward_id"]})

        updates = compute_priority_score(issue, ward)
        if updates["is_escalated"] and not issue.get("is_escalated"):
            updates["escalated_at"] = now_utc()

        await db.issues.update_one(
            {"_id": issue["_id"]},
            {"$set": updates}
        )
        count += 1

    return count
