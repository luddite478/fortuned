from fastapi import APIRouter, Request, Query, Body
from typing import Optional
from http_api.users import (
    login_handler, 
    register_handler, 
    get_user_handler, 
    get_users_handler,
    LoginRequest,
    RegisterRequest
)
from http_api.threads import (
    create_thread_handler,
    join_thread_handler,
    get_threads_handler,
    get_thread_handler,
    update_thread_handler,
    send_invitation_handler,
    manage_invitation_handler,
    get_messages_handler,
    create_message_handler,
)
from typing import Dict, Any
import json

router = APIRouter()

# Health check endpoint
@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "version": "1.0"}

# Authentication endpoints
@router.post("/auth/login")
async def login(request: Request, login_data: LoginRequest):
    """User login with email and password"""
    return await login_handler(request, login_data)

@router.post("/auth/register")
async def register(request: Request, register_data: RegisterRequest):
    """User registration"""
    return await register_handler(request, register_data)

# User endpoints (renamed from profile endpoints)
@router.get("/users/user")
async def get_user(request: Request, id: str = Query(...), token: str = Query(...)):
    """Get user by ID"""
    return await get_user_handler(request, id, token)

@router.get("/users/list")
async def get_users(request: Request, token: str = Query(...), limit: int = Query(20), offset: int = Query(0)):
    """Get list of users"""
    return await get_users_handler(request, token, limit, offset)

# Threads endpoints (new paths)
@router.get("/threads")
async def get_threads(request: Request, token: str = Query(...), limit: int = Query(20), offset: int = Query(0), user_id: Optional[str] = Query(None)):
    """Get list of threads (new path)"""
    return await get_threads_handler(request, token, limit, offset, user_id)

@router.get("/threads/{thread_id}")
async def get_thread_by_path(request: Request, thread_id: str, token: str = Query(...)):
    """Get thread by ID (new path)"""
    return await get_thread_handler(request, thread_id, token)

@router.post("/threads")
async def create_thread_new(request: Request, thread_data: dict):
    """Create new thread (new path)"""
    return await create_thread_handler(request, thread_data)

@router.post("/threads/{thread_id}/users")
async def join_thread(request: Request, thread_id: str, user_data: Dict[str, Any] = Body(...)):
    return await join_thread_handler(request, thread_id, user_data)

@router.put("/threads/{thread_id}")
async def update_thread(request: Request, thread_id: str, update_data: Dict[str, Any] = Body(...)):
    return await update_thread_handler(request, thread_id, update_data)

@router.post("/threads/{thread_id}/invites")
async def send_invitation(request: Request, thread_id: str, invitation_data: Dict[str, Any] = Body(...)):
    """Send invitation to user for a thread"""
    return await send_invitation_handler(request, thread_id, invitation_data)

@router.put("/threads/{thread_id}/invites/{user_id}")
async def manage_invitation(request: Request, thread_id: str, user_id: str, action_data: Dict[str, Any] = Body(...)):
    """Accept or decline thread invitation"""
    return await manage_invitation_handler(request, thread_id, user_id, action_data)

# Messages endpoints
@router.get("/messages")
async def get_messages(request: Request, thread_id: str = Query(...), token: str = Query(...)):
    """List messages for a thread"""
    return await get_messages_handler(request, thread_id, token)

@router.post("/messages")
async def create_message(request: Request, message_data: Dict[str, Any] = Body(...)):
    """Create a message (snapshot) for a thread"""
    return await create_message_handler(request, message_data)
