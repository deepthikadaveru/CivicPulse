# CivicPulse API

Municipal issue reporting platform — FastAPI + MongoDB Atlas.  
No Docker. No paid services. Runs directly on your machine.

---

## Stack

| Layer | Technology | Cost |
|---|---|---|
| API framework | FastAPI + Uvicorn | Free |
| Database | MongoDB Atlas (free tier) | Free |
| Media storage | Local filesystem | Free |
| Auth | JWT (phone + OTP) | Free |
| OTP delivery | Console / response (dev) | Free |
| AI classification | OpenAI GPT-4o (optional) | Pay-per-use |

---

## Project Structure

```
civicpulse/
├── main.py                  ← FastAPI app, startup, routing
├── requirements.txt
├── .env.example
│
├── core/
│   ├── config.py            ← Settings from .env
│   ├── database.py          ← MongoDB Atlas connection + indexes
│   ├── auth.py              ← JWT creation + user dependency
│   └── utils.py             ← ObjectId serialization helpers
│
├── models/
│   └── schemas.py           ← Pydantic request/response models
│
├── routers/
│   ├── auth.py              ← POST /auth/send-otp, /auth/verify-otp, /auth/me
│   ├── cities.py            ← GET/POST /cities
│   ├── departments.py       ← GET /departments, /departments/categories
│   ├── issues.py            ← Full issue CRUD + upvote + map pins
│   ├── notifications.py     ← GET /notifications
│   └── admin.py             ← Seed data, recalculate scores, promote users
│
├── services/
│   ├── otp_service.py       ← Generate + verify OTP (returns in response for dev)
│   ├── priority_engine.py   ← Score calculation + starvation floor + escalation
│   ├── duplicate_detector.py← MongoDB $nearSphere query
│   ├── classifier.py        ← OpenAI GPT-4o Vision (optional)
│   └── media_service.py     ← Local photo/video storage + thumbnails
│
└── media/                   ← Created automatically on startup
    ├── issues/              ← Uploaded photos and videos
    └── thumbs/              ← Auto-generated thumbnails
```

---

## Setup

### 1. Get the code

```bash
cd civicpulse
```

### 2. Create a virtual environment

```bash
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Set up MongoDB Atlas (free)

1. Go to [https://cloud.mongodb.com](https://cloud.mongodb.com) → Create a free account
2. Create a **free M0 cluster** (512 MB, more than enough to start)
3. Under **Database Access** → Add a database user with a password
4. Under **Network Access** → Add IP Address → `0.0.0.0/0` (allow all for dev)
5. Click **Connect** → **Drivers** → Copy the connection string
   - It looks like: `mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/`

### 5. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
MONGODB_URL=mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
MONGODB_DB_NAME=civicpulse
JWT_SECRET=any-long-random-string-here
```

To generate a strong JWT secret:
```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

### 6. Run the server

```bash
uvicorn main:app --reload
```

The API is now live at **http://localhost:8000**  
Interactive docs at **http://localhost:8000/docs**

---

## First-Time Setup (via API)

### Step 1 — Create your super admin account

```bash
# Send OTP (OTP is returned in response during dev)
curl -X POST http://localhost:8000/api/v1/auth/send-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+919999999999"}'

# Verify OTP and get token
curl -X POST http://localhost:8000/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+919999999999", "otp": "123456", "name": "Admin"}'
```

Save the `access_token` from the response.

### Step 2 — Promote your account to super_admin

Go to **MongoDB Atlas** → Browse Collections → `civicpulse` → `users`  
Find your user document and change `"role": "citizen"` to `"role": "super_admin"`.

(You only need to do this once for the first admin. After that, use the `/admin/make-official` endpoint.)

### Step 3 — Create a city

```bash
curl -X POST http://localhost:8000/api/v1/cities/ \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Hyderabad", "state": "Telangana", "population": 9000000}'
```

Copy the `id` from the response.

### Step 4 — Seed departments and categories

```bash
curl -X POST http://localhost:8000/api/v1/admin/seed/YOUR_CITY_ID \
  -H "Authorization: Bearer YOUR_TOKEN"
```

This creates all 6 departments (Roads, Water, Electricity, Horticulture, Waste, Others)  
and all 20 issue categories automatically.

---

## API Reference

### Authentication

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/auth/send-otp` | None | Send OTP to phone number |
| POST | `/api/v1/auth/verify-otp` | None | Verify OTP → get JWT token |
| GET  | `/api/v1/auth/me` | Required | Current user profile |
| POST | `/api/v1/auth/fcm-token` | Required | Save push notification token |

**OTP flow (dev mode):**
```json
POST /api/v1/auth/send-otp
{ "phone_number": "+919876543210" }

Response:
{
  "message": "OTP sent successfully",
  "otp": "847291",              ← use this to verify
  "expires_in_minutes": 10,
  "dev_note": "Remove otp field in production"
}
```

```json
POST /api/v1/auth/verify-otp
{ "phone_number": "+919876543210", "otp": "847291", "name": "Ravi Kumar" }

Response:
{
  "access_token": "eyJ...",
  "token_type": "bearer",
  "user": { "id": "...", "name": "Ravi Kumar", "role": "citizen", "is_new": true }
}
```

All subsequent requests: `Authorization: Bearer eyJ...`

---

### Issues

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/issues/` | Required | Report a new issue (multipart/form-data) |
| GET  | `/api/v1/issues/` | None | List issues with filters |
| GET  | `/api/v1/issues/map-pins` | None | Issues in map viewport |
| GET  | `/api/v1/issues/check-nearby` | None | Find nearby duplicates |
| GET  | `/api/v1/issues/{id}` | None | Full issue detail |
| POST | `/api/v1/issues/{id}/upvote` | Required | Toggle upvote |
| POST | `/api/v1/issues/{id}/confirm-category` | Required | Confirm/change AI category |
| POST | `/api/v1/issues/{id}/update-status` | Official | Update status |
| POST | `/api/v1/issues/{id}/comment` | Required | Add comment |

**Report an issue (multipart form):**
```
POST /api/v1/issues/
Content-Type: multipart/form-data

title=Large pothole near bus stop
description=Very deep, vehicles swerving
latitude=17.3850
longitude=78.4867
address=MG Road, near bus stop 4
road_type=main_road
category_id=<id>
city_id=<id>
photo=<file>      ← optional
video=<file>      ← optional
```

**Map pins (for the public map):**
```
GET /api/v1/issues/map-pins?min_lng=78.4&min_lat=17.3&max_lng=78.5&max_lat=17.4&status=active&city_id=<id>
```

**Check for nearby duplicates before reporting:**
```
GET /api/v1/issues/check-nearby?latitude=17.385&longitude=78.486&category_id=<id>&city_id=<id>
```

**Filter parameters for list:**
- `city_id` — filter by city
- `status` — pending | verified | assigned | in_progress | resolved | rejected
- `severity` — low | moderate | high | critical
- `department_id` — filter by department
- `page`, `limit` — pagination

---

### Departments

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/departments/?city_id=<id>` | None | List departments |
| GET | `/api/v1/departments/categories?city_id=<id>` | None | All categories (for app picker) |

---

### Admin

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/admin/seed/{city_id}` | Super admin | Seed depts + categories |
| POST | `/api/v1/admin/recalculate-scores` | Super admin | Recalculate all priority scores |
| POST | `/api/v1/admin/make-official` | Super admin | Promote user to official role |

---

## Priority Scoring

```
score = (report_count × 2.0)
      + (upvote_count × 1.5)
      + (population_density / 1000 × 0.8)   capped at 10
      + (road_type_weight × 1.2)             highway=3, main_road=2, lane=1
      + (near_school_or_hospital × 1.0)
      × category_base_weight

# Starvation floor (so low-report issues are never buried forever):
if report_count < 3:
    score = max(score, days_open × 0.5)
```

| Score | Severity | Map pin |
|---|---|---|
| ≥ 40 | Critical | Pulsing red |
| ≥ 20 | High | Red |
| ≥ 8 | Moderate | Orange |
| < 8 | Low | Yellow |
| Resolved | — | Green |

Auto-escalation: score ≥ 50 OR open ≥ 30 days → `is_escalated: true`

---

## User Roles

| Role | Permissions |
|---|---|
| `citizen` | Report, upvote, view map, track own reports |
| `dept_official` | View dept queue, update status, add official comments |
| `city_admin` | All departments in their city |
| `super_admin` | Everything — seed data, promote users, all cities |

---

## Adding AI Classification (Optional)

If you add an OpenAI API key to `.env`:
```env
OPENAI_API_KEY=sk-...
```

When a citizen uploads a photo without selecting a category, the API will automatically call GPT-4o Vision, analyse the photo + description, and return an `ai_suggested_category_name` and `ai_confidence` score. The citizen then confirms or overrides it.

Without the key, classification is skipped and the citizen selects the category manually — the app works fine either way.

---

## Production Checklist

- [ ] Set `DEBUG=false` in `.env`
- [ ] Change `JWT_SECRET` to a strong random value
- [ ] Remove `"otp"` field from `send_otp()` return in `services/otp_service.py`
- [ ] Integrate a real SMS provider (MSG91 / Fast2SMS both have free tiers for India)
- [ ] Restrict `CORS` origins in `main.py`
- [ ] Set up a cron job or APScheduler to call `/admin/recalculate-scores` nightly
- [ ] Add Firebase Cloud Messaging for push notifications
- [ ] Move media to Cloudflare R2 (free 10GB/month) when local storage fills up
