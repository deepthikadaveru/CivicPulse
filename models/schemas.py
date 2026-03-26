from pydantic import BaseModel, Field
from typing import Optional, List
from enum import Enum
from datetime import datetime


# ─── Enums ────────────────────────────────────────────────────────────────────

class UserRole(str, Enum):
    CITIZEN = "citizen"
    DEPT_OFFICIAL = "dept_official"
    CITY_ADMIN = "city_admin"
    SUPER_ADMIN = "super_admin"


class IssueStatus(str, Enum):
    PENDING = "pending"
    VERIFIED = "verified"
    ASSIGNED = "assigned"
    IN_PROGRESS = "in_progress"
    RESOLVED = "resolved"
    REJECTED = "rejected"


class IssueSeverity(str, Enum):
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"
    CRITICAL = "critical"


class RoadType(str, Enum):
    HIGHWAY = "highway"
    MAIN_ROAD = "main_road"
    LANE = "lane"
    NONE = "none"


class MediaType(str, Enum):
    PHOTO = "photo"
    VIDEO = "video"


# ─── Auth ─────────────────────────────────────────────────────────────────────

class SendOTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=15)


class VerifyOTPRequest(BaseModel):
    phone_number: str
    otp: str
    name: Optional[str] = ""


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict


class UpdateFCMTokenRequest(BaseModel):
    fcm_token: str


# ─── Issues ───────────────────────────────────────────────────────────────────

class GeoPoint(BaseModel):
    """GeoJSON Point for MongoDB 2dsphere index."""
    type: str = "Point"
    coordinates: List[float]  # [longitude, latitude]


class IssueCreateRequest(BaseModel):
    title: str = Field(..., min_length=5, max_length=200)
    description: Optional[str] = ""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    address: Optional[str] = ""
    road_type: RoadType = RoadType.NONE
    category_id: Optional[str] = None
    city_id: str


class IssueStatusUpdateRequest(BaseModel):
    status: IssueStatus
    note: Optional[str] = ""


class ConfirmCategoryRequest(BaseModel):
    category_id: str


class AddCommentRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1000)


class UpvoteResponse(BaseModel):
    status: str
    upvote_count: int


# ─── Cities ───────────────────────────────────────────────────────────────────

class CityCreateRequest(BaseModel):
    name: str
    state: str
    country: str = "India"
    population: int = 0


# ─── Departments ──────────────────────────────────────────────────────────────

class DepartmentCreateRequest(BaseModel):
    name: str
    code: str
    city_id: str
    sla_days: int = 30
    email: Optional[str] = ""
    phone: Optional[str] = ""


class CategoryCreateRequest(BaseModel):
    name: str
    slug: str
    department_id: str
    description: Optional[str] = ""
    icon: Optional[str] = ""
    base_priority_weight: float = 1.0
