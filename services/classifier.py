"""
AI classification using OpenAI GPT-4o Vision.
Completely optional — if OPENAI_API_KEY is not set, classification is skipped
and the user manually selects the category.
"""
import json
import base64
import logging
from core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


async def classify_issue(image_path: str, description: str, categories: list) -> dict:
    """
    Analyses the photo + description and suggests the best category.

    categories: list of {"slug": ..., "name": ..., "department_name": ...}

    Returns:
    {
        "category_slug": "pothole",
        "department_name": "Roads",
        "confidence": 0.92,
        "reasoning": "..."
    }
    """
    if not settings.OPENAI_API_KEY:
        return _no_ai_response()

    try:
        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        with open(image_path, "rb") as f:
            image_b64 = base64.b64encode(f.read()).decode("utf-8")

        ext = image_path.rsplit(".", 1)[-1].lower()
        mime = "image/jpeg" if ext in ("jpg", "jpeg") else f"image/{ext}"

        category_list = "\n".join(
            f"- slug: {c['slug']}, name: {c['name']}, dept: {c.get('department_name', '')}"
            for c in categories
        )

        prompt = f"""You are an AI assistant for a municipal issue reporting platform in India.

Analyse the image and the description, then classify the civic issue.

User description: "{description}"

Available categories:
{category_list}

Respond ONLY with valid JSON — no markdown, no explanation outside the JSON:
{{
  "category_slug": "<slug from the list>",
  "department_name": "<dept name>",
  "confidence": <float 0.0–1.0>,
  "reasoning": "<one sentence>"
}}"""

        response = await client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{image_b64}"}},
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
            max_tokens=200,
        )

        raw = response.choices[0].message.content.strip()
        result = json.loads(raw)
        return result

    except Exception as e:
        logger.error(f"AI classification error: {e}")
        return _no_ai_response()


def _no_ai_response() -> dict:
    return {
        "category_slug": None,
        "department_name": None,
        "confidence": 0.0,
        "reasoning": "AI classification not available. Please select category manually.",
    }
