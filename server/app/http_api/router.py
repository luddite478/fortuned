from fastapi import APIRouter, Request, Query
from http_api.rate_limiter import check_rate_limit
import json
from typing import Optional

router = APIRouter()

@router.get("/")
async def api_handler(
    request: Request, 
    action: str = Query(..., description="Action to perform"),
    data: Optional[str] = Query(None, description="Optional JSON data"),
    payload: Optional[str] = Query(None, description="Alternative: full JSON payload")
):
    """Single API endpoint - supports both query params and JSON payload"""
    check_rate_limit(request)
    
    if payload is None:
        result = {
            "action": action,
            "data": json.loads(data) if data else None
        }
    else:
        result = json.loads(payload)
    
    return {"received": result}
