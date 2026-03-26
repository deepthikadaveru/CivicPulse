from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from pathlib import Path
import traceback

from core.config import get_settings
from core.database import connect_db, close_db
from routers import auth, cities, departments, issues, notifications, admin

settings = get_settings()

Path(settings.MEDIA_DIR).mkdir(parents=True, exist_ok=True)
Path(f"{settings.MEDIA_DIR}/issues").mkdir(parents=True, exist_ok=True)
Path(f"{settings.MEDIA_DIR}/thumbs").mkdir(parents=True, exist_ok=True)
@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db()
    yield
    await close_db()


app = FastAPI(
    title="CivicPulse API",
    description="Municipal issue reporting platform — FastAPI + MongoDB",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.DEBUG else ["https://your-domain.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if settings.DEBUG:
    @app.exception_handler(Exception)
    async def debug_exception_handler(request: Request, exc: Exception):
        return JSONResponse(
            status_code=500,
            content={
                "error": type(exc).__name__,
                "detail": str(exc),
                "traceback": traceback.format_exc(),
            }
        )

app.mount("/media", StaticFiles(directory=settings.MEDIA_DIR), name="media")

app.include_router(auth.router,          prefix="/api/v1")
app.include_router(cities.router,        prefix="/api/v1")
app.include_router(departments.router,   prefix="/api/v1")
app.include_router(issues.router,        prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(admin.router,         prefix="/api/v1")


@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "version": "1.0.0",
        "docs": "/docs",
        "status": "running",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}

app.mount("/portal", StaticFiles(directory="portal", html=True), name="portal")