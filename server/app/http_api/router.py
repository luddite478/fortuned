# routes/router.py
from fastapi import APIRouter, Request
from http_api.rate_limiter import check_rate_limit
import os

router = APIRouter()

API_TOKEN = os.getenv("API_TOKEN")

@router.get("/get_sound_series")
async def get_sound_series(request: Request, token: str = ""):
    check_rate_limit(request)

    if token != API_TOKEN:
        return {"error": "Unauthorized"}, 401

    # Simulated data
    return {
        "series": [
            {"id": 1, "name": "Alpha"},
            {"id": 2, "name": "Beta"},
            {"id": 3, "name": "Gamma"}
        ]
    }
