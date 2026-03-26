import certifi
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from core.config import get_settings

settings = get_settings()

client: AsyncIOMotorClient = None
db: AsyncIOMotorDatabase = None


async def connect_db():
    global client, db

    client = AsyncIOMotorClient(
        settings.MONGODB_URL,
        tls=True,
        tlsCAFile=certifi.where(),
        serverSelectionTimeoutMS=30000,
    )

    db = client[settings.MONGODB_DB_NAME]

    # Force connection check first
    await client.admin.command("ping")

    await _create_indexes()
    print(f"Connected to MongoDB: {settings.MONGODB_DB_NAME}")


async def close_db():
    global client
    if client:
        client.close()
        print("MongoDB connection closed")


async def get_db() -> AsyncIOMotorDatabase:
    return db


async def _create_indexes():
    await db.users.create_index("phone_number", unique=True)
    await db.users.create_index("role")
    await db.otp_sessions.create_index("phone_number")
    await db.otp_sessions.create_index(
        "expires_at", expireAfterSeconds=0
    )
    await db.cities.create_index("is_active")
    await db.departments.create_index("city_id")
    await db.departments.create_index("code")
    await db.issue_categories.create_index("department_id")
    await db.issue_categories.create_index("slug")
    await db.issues.create_index("city_id")
    await db.issues.create_index("status")
    await db.issues.create_index("department_id")
    await db.issues.create_index("reporter_id")
    await db.issues.create_index([("priority_score", -1)])
    await db.issues.create_index([("city_id", 1), ("status", 1)])
    await db.issues.create_index([("city_id", 1), ("priority_score", -1)])
    await db.issues.create_index([("location", "2dsphere")])
    await db.issue_votes.create_index(
        [("issue_id", 1), ("user_id", 1)], unique=True
    )
    await db.notifications.create_index("user_id")
    await db.notifications.create_index("is_read")
    print("MongoDB indexes created")
