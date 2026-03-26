"""
Local media storage service.
Saves uploaded photos/videos to the /media/issues/ directory.
To switch to cloud storage later, only this file needs to change.
"""
import os
import uuid
import aiofiles
from pathlib import Path
from PIL import Image
from datetime import datetime
from fastapi import UploadFile, HTTPException
from core.config import get_settings

settings = get_settings()

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/quicktime", "video/x-msvideo"}
MAX_IMAGE_SIZE_MB = 10
MAX_VIDEO_SIZE_MB = 100


def _get_upload_dir() -> Path:
    today = datetime.now().strftime("%Y/%m/%d")
    path = Path(settings.MEDIA_DIR) / "issues" / today
    path.mkdir(parents=True, exist_ok=True)
    return path


def _get_thumb_dir() -> Path:
    today = datetime.now().strftime("%Y/%m/%d")
    path = Path(settings.MEDIA_DIR) / "thumbs" / today
    path.mkdir(parents=True, exist_ok=True)
    return path


async def save_media(file: UploadFile) -> dict:
    """
    Saves an uploaded file to disk.
    Returns {"file_path": ..., "thumbnail_path": ..., "media_type": ...}
    """
    content_type = file.content_type or ""

    if content_type in ALLOWED_IMAGE_TYPES:
        media_type = "photo"
        max_mb = MAX_IMAGE_SIZE_MB
    elif content_type in ALLOWED_VIDEO_TYPES:
        media_type = "video"
        max_mb = MAX_VIDEO_SIZE_MB
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {content_type}. Allowed: JPEG, PNG, WebP, MP4, MOV, AVI"
        )

    ext = content_type.split("/")[-1].replace("quicktime", "mov").replace("x-msvideo", "avi")
    filename = f"{uuid.uuid4().hex}.{ext}"

    upload_dir = _get_upload_dir()
    file_path = upload_dir / filename

    # Stream write to avoid loading entire file in memory
    contents = await file.read()
    size_mb = len(contents) / (1024 * 1024)
    if size_mb > max_mb:
        raise HTTPException(status_code=400, detail=f"File too large. Max {max_mb}MB allowed.")

    async with aiofiles.open(file_path, "wb") as f:
        await f.write(contents)

    thumbnail_path = None
    if media_type == "photo":
        thumbnail_path = _make_thumbnail(file_path)

    return {
        "file_path": str(file_path),
        "thumbnail_path": str(thumbnail_path) if thumbnail_path else None,
        "media_type": media_type,
        "original_filename": file.filename,
        "size_bytes": len(contents),
    }


def _make_thumbnail(image_path: Path) -> Path:
    """Creates a 400x300 thumbnail from the image."""
    try:
        thumb_dir = _get_thumb_dir()
        thumb_path = thumb_dir / f"thumb_{image_path.name}"
        with Image.open(image_path) as img:
            img.thumbnail((400, 300))
            img.save(thumb_path, optimize=True, quality=75)
        return thumb_path
    except Exception:
        return None


def get_media_url(file_path: str) -> str:
    """Convert a local file path to a URL served by FastAPI's StaticFiles."""
    if not file_path:
        return None
    return f"/media/{Path(file_path).relative_to(settings.MEDIA_DIR)}"
