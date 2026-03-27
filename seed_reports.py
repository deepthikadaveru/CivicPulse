"""
Seed random civic issue reports across Telangana.
Run: python seed_reports.py

Make sure your backend is running first:
  uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import requests
import random
import time

# ── Config ────────────────────────────────────────────────────────────────────
BASE_URL   = "http://127.0.0.1:8000/api/v1"
PHONE      = "+919885211699"   # your phone number (already registered)
NUM_REPORTS = 40               # how many fake reports to create

# ── Telangana bounding box ────────────────────────────────────────────────────
# Covers the entire state roughly
LAT_MIN, LAT_MAX = 15.8, 19.9
LNG_MIN, LNG_MAX = 77.2, 81.3

# More weight towards Hyderabad area so the heatmap looks realistic
HYDERABAD_CLUSTERS = [
    (17.3850, 78.4867, 0.4),   # Hyderabad centre — 40% of reports
    (17.4500, 78.3800, 0.15),  # Kukatpally
    (17.4900, 78.3900, 0.10),  # HITEC City
    (17.3600, 78.5500, 0.10),  # LB Nagar
    (17.3200, 78.5500, 0.08),  # Dilsukhnagar
    (18.0000, 79.5800, 0.05),  # Warangal
    (17.0000, 79.0900, 0.05),  # Nalgonda
    (18.4500, 79.1200, 0.07),  # Karimnagar
]

# ── Issue data ────────────────────────────────────────────────────────────────
TITLES = [
    "Large pothole causing accidents",
    "Drainage blocked for weeks",
    "Street light not working",
    "Overgrown tree blocking road",
    "Sewage overflow on road",
    "Power line hanging dangerously",
    "Road completely damaged after rain",
    "Garbage not collected for days",
    "Water supply pipe leaking",
    "Broken footpath near school",
    "Transformer making loud noise",
    "Flooding during rains",
    "Illegal dumping near park",
    "Fallen tree blocking traffic",
    "Missing road divider",
    "Open manhole on main road",
    "Street light flickering all night",
    "Pothole filled with rainwater",
    "Garbage bin overflowing",
    "Road cave-in near junction",
    "Stray dogs attacking people",
    "Broken water pipe flooding street",
    "No street lights in entire area",
    "Tree roots breaking footpath",
    "Drainage overflow into homes",
]

DESCRIPTIONS = [
    "This has been going on for weeks now. Very dangerous especially at night.",
    "Multiple vehicles have been damaged. Needs immediate attention.",
    "Residents have complained multiple times but no action taken.",
    "Very dangerous for two-wheelers especially during night.",
    "Children walking to school are at risk.",
    "The smell is unbearable. Health hazard for residents.",
    "Causing major traffic jams every morning.",
    "Elderly people find it very difficult to walk here.",
    "Has been reported before but still not fixed.",
    "Getting worse with every rain. Urgent repair needed.",
]

AREAS = [
    "Near main bus stop", "Junction area", "Residential colony",
    "Near government school", "Market area", "Near hospital",
    "Main road", "Behind railway station", "Near temple",
    "Industrial area", "Near park", "College road",
]

ROAD_TYPES = ["highway", "main_road", "lane", "none"]

# ── Helper: pick a weighted random location ───────────────────────────────────
def random_location():
    r = random.random()
    cumulative = 0.0
    for lat, lng, weight in HYDERABAD_CLUSTERS:
        cumulative += weight
        if r < cumulative:
            # Add some scatter around the cluster centre
            return (
                lat  + random.uniform(-0.08, 0.08),
                lng  + random.uniform(-0.08, 0.08),
            )
    # Fallback: random point anywhere in Telangana
    return (
        random.uniform(LAT_MIN, LAT_MAX),
        random.uniform(LNG_MIN, LNG_MAX),
    )

# ── Step 1: Login ─────────────────────────────────────────────────────────────
def login():
    print("Logging in...")
    r = requests.post(f"{BASE_URL}/auth/send-otp", json={"phone_number": PHONE})
    r.raise_for_status()
    otp = r.json().get("otp")
    print(f"OTP: {otp}")

    r = requests.post(f"{BASE_URL}/auth/verify-otp", json={
        "phone_number": PHONE,
        "otp": otp,
        "name": "",
    })
    r.raise_for_status()
    token = r.json()["access_token"]
    print("Logged in successfully!")
    return token

# ── Step 2: Get city + categories ─────────────────────────────────────────────
def get_city_and_categories(token):
    headers = {"Authorization": f"Bearer {token}"}

    cities = requests.get(f"{BASE_URL}/cities/", headers=headers).json()
    if not cities:
        raise Exception("No cities found! Run the seed endpoint first.")
    city = cities[0]
    print(f"City: {city['name']} ({city['id']})")

    cats = requests.get(
        f"{BASE_URL}/departments/categories?city_id={city['id']}",
        headers=headers
    ).json()
    if not cats:
        raise Exception("No categories found! Run POST /admin/seed/{city_id} first.")
    print(f"Found {len(cats)} categories")

    return city["id"], cats

# ── Step 3: Submit a single report ────────────────────────────────────────────
def submit_report(token, city_id, categories, index):
    headers = {"Authorization": f"Bearer {token}"}
    lat, lng = random_location()
    category = random.choice(categories)
    title    = random.choice(TITLES)
    desc     = random.choice(DESCRIPTIONS)
    area     = random.choice(AREAS)
    road_type = random.choice(ROAD_TYPES)

    # Skip road type for non-road categories
    road_slugs = {"pothole","road-damage","broken-footpath","missing-sign","drainage-blocked","flooding"}
    if category["slug"] not in road_slugs:
        road_type = "none"

    address = f"{area}, {category.get('department_name','')}, Telangana"

    data = {
        "title":       title,
        "description": desc,
        "latitude":    str(round(lat, 6)),
        "longitude":   str(round(lng, 6)),
        "address":     address,
        "road_type":   road_type,
        "city_id":     city_id,
        "category_id": category["id"],
    }

    # Use a placeholder 1x1 pixel image (no real photo needed for demo)
    tiny_png = (
        b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01'
        b'\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00'
        b'\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18'
        b'\xd8N\x00\x00\x00\x00IEND\xaeB`\x82'
    )

    files = {"photo": ("photo.png", tiny_png, "image/png")}

    r = requests.post(
        f"{BASE_URL}/issues/",
        headers=headers,
        data=data,
        files=files,
    )

    if r.status_code == 200:
        issue = r.json()
        print(f"  [{index+1:02d}] ✓ {title[:40]:<40} | {category['name']:<25} | score: {issue.get('priority_score',0)}")
    else:
        print(f"  [{index+1:02d}] ✗ Failed ({r.status_code}): {r.text[:80]}")

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("  CivicPulse — Telangana Report Seeder")
    print("=" * 60)

    token = login()
    city_id, categories = get_city_and_categories(token)

    print(f"\nSubmitting {NUM_REPORTS} reports across Telangana...\n")

    for i in range(NUM_REPORTS):
        submit_report(token, city_id, categories, i)
        time.sleep(0.3)  # small delay to avoid overwhelming the server

    print(f"\n{'='*60}")
    print(f"  Done! {NUM_REPORTS} reports submitted.")
    print(f"  Open the map to see them: http://127.0.0.1:8000/portal/")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()