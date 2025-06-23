from fastapi import APIRouter, Request, Query, Body
from http_api.rate_limiter import check_rate_limit
from http_api.users import get_user_profile_handler, get_user_profiles_handler
from http_api.threads import (
    create_thread_handler, 
    add_checkpoint_handler, 
    join_thread_handler, 
    get_threads_handler, 
    get_thread_handler, 
    update_thread_handler
)
from typing import Dict, Any, Optional
import json

router = APIRouter()

# Legacy generic endpoint
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

# User endpoints
@router.get("/users/profile")
async def get_user_profile(request: Request, id: str = Query(...), token: str = Query(...)):
    return await get_user_profile_handler(request, id, token)

@router.get("/users/profiles")
async def get_user_profiles(request: Request, token: str = Query(...), limit: int = Query(20), offset: int = Query(0)):
    return await get_user_profiles_handler(request, token, limit, offset)

# Thread endpoints
@router.post("/threads")
async def create_thread(request: Request, thread_data: Dict[str, Any] = Body(...)):
    return await create_thread_handler(request, thread_data)

@router.post("/threads/{thread_id}/checkpoints")
async def add_checkpoint(request: Request, thread_id: str, checkpoint_data: Dict[str, Any] = Body(...)):
    return await add_checkpoint_handler(request, thread_id, checkpoint_data)

@router.post("/threads/{thread_id}/users")
async def join_thread(request: Request, thread_id: str, user_data: Dict[str, Any] = Body(...)):
    return await join_thread_handler(request, thread_id, user_data)

@router.get("/threads")
async def get_threads(request: Request, token: str = Query(...), limit: int = Query(50), offset: int = Query(0), user_id: Optional[str] = Query(None)):
    return await get_threads_handler(request, token, limit, offset, user_id)

@router.get("/threads/{thread_id}")
async def get_thread(request: Request, thread_id: str, token: str = Query(...)):
    return await get_thread_handler(request, thread_id, token)

@router.put("/threads/{thread_id}")
async def update_thread(request: Request, thread_id: str, update_data: Dict[str, Any] = Body(...)):
    return await update_thread_handler(request, thread_id, update_data)

# Project endpoints (aliases for threads for backward compatibility)  
@router.get("/projects/user")
async def get_user_projects(request: Request, user_id: str = Query(...), token: str = Query(...), limit: int = Query(50), offset: int = Query(0)):
    """Get projects (threads) for a specific user - alias for threads endpoint"""
    return await get_threads_handler(request, token, limit, offset, user_id)

@router.get("/projects")
async def get_projects(request: Request, token: str = Query(...), limit: int = Query(50), offset: int = Query(0), user_id: Optional[str] = Query(None)):
    """Get projects (threads) - alias for threads endpoint"""
    return await get_threads_handler(request, token, limit, offset, user_id)

@router.get("/projects/{project_id}")
async def get_project(request: Request, project_id: str, token: str = Query(...)):
    """Get specific project (thread) - alias for thread endpoint"""
    return await get_thread_handler(request, project_id, token)
