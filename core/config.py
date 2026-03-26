from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    MONGODB_URL: str = "mongodb://localhost:27017"
    MONGODB_DB_NAME: str = "civicpulse"

    JWT_SECRET: str = "change-this-secret"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 43200  # 30 days

    MEDIA_DIR: str = "media"
    OPENAI_API_KEY: str = ""
    APP_NAME: str = "CivicPulse"
    DEBUG: bool = True

    # Priority engine weights
    WEIGHT_REPORT_COUNT: float = 2.0
    WEIGHT_UPVOTES: float = 1.5
    WEIGHT_POPULATION_DENSITY: float = 0.8
    WEIGHT_ROAD_TYPE: float = 1.2
    WEIGHT_SENSITIVE_LOCATION: float = 1.0
    STARVATION_FLOOR_PER_DAY: float = 0.5
    ESCALATION_SCORE_THRESHOLD: float = 50.0
    ESCALATION_DAYS_THRESHOLD: int = 30

    class Config:
        env_file = ".env"
        extra = "ignore"


@lru_cache
def get_settings() -> Settings:
    return Settings()
