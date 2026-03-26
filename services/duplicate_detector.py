"""
Finds existing open issues near a given GPS point using MongoDB's
$nearSphere geospatial operator (requires 2dsphere index).
"""

DUPLICATE_RADIUS_METERS = 100


async def find_nearby_issues(
    latitude: float,
    longitude: float,
    category_id: str,
    city_id: str,
    db,
) -> list:
    """
    Returns open issues within DUPLICATE_RADIUS_METERS of the point
    with the same category, closest first.
    """
    cursor = db.issues.find(
        {
            "city_id": city_id,
            "category_id": category_id,
            "status": {"$nin": ["resolved", "rejected"]},
            "location": {
                "$nearSphere": {
                    "$geometry": {
                        "type": "Point",
                        "coordinates": [longitude, latitude],
                    },
                    "$maxDistance": DUPLICATE_RADIUS_METERS,
                }
            },
        }
    ).limit(5)

    results = []
    async for doc in cursor:
        results.append(doc)
    return results
