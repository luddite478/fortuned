# routes/router.py
from fastapi import APIRouter, Request, Query, HTTPException, Body
from http_api.rate_limiter import check_rate_limit
import json
import os
from typing import Optional, Dict, List, Any
from datetime import datetime
from pymongo import MongoClient
import uuid

router = APIRouter()

# MongoDB connection with authentication
MONGO_URL = "mongodb://admin:test@mongodb:27017/admin?authSource=admin"
DATABASE_NAME = "admin"

# API Token for authentication (hardcoded for testing)
API_TOKEN = "asdfasdasduiu546"

def get_db():
    """Get database connection"""
    client = MongoClient(MONGO_URL)
    return client[DATABASE_NAME]

def verify_token(token: str):
    """Verify API token and raise HTTPException if invalid"""
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

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

@router.get("/users/profile")
async def get_user_profile(request: Request, id: str = Query(..., description="User ID"), token: str = Query(..., description="API Token")):
    """Get clean user profile by ID from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        profile = db.profiles.find_one({"id": id}, {"_id": 0})
        
        if not profile:
            raise HTTPException(status_code=404, detail=f"User profile not found: {id}")
        
        return profile
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/users/profiles")
async def get_user_profiles(
    request: Request, 
    token: str = Query(..., description="API Token"),
    limit: int = Query(20, description="Number of results"),
    offset: int = Query(0, description="Offset for pagination")
):
    """Get list of all user profiles from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Get total count for pagination
        total = db.profiles.count_documents({})
        
        # Get users with pagination, sorted by registration date (newest first)
        users_cursor = db.profiles.find(
            {}, 
            {
                "_id": 0,
                "id": 1,
                "name": 1,
                "registered_at": 1,
                "last_online": 1,
                "email": 1,
                "info": 1
            }
        ).sort("registered_at", -1).limit(limit).skip(offset)
        
        users_list = list(users_cursor)
        
        return {
            "profiles": users_list,
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

# THREADS ENDPOINTS

@router.post("/threads")
async def create_thread(
    request: Request,
    thread_data: Dict[str, Any] = Body(...),
):
    """Create a new thread"""
    check_rate_limit(request)
    verify_token(thread_data.get("token", ""))
    
    try:
        db = get_db()
        
        # Generate unique thread ID
        thread_id = str(uuid.uuid4())
        current_time = datetime.utcnow().isoformat() + "Z"
        
        # Extract data from request
        title = thread_data.get("title", "Untitled Thread")
        users = thread_data.get("users", [])
        initial_checkpoint = thread_data.get("initial_checkpoint", {})
        metadata = thread_data.get("metadata", {})
        
        # Ensure initial checkpoint has required fields
        if not initial_checkpoint.get("id"):
            initial_checkpoint["id"] = str(uuid.uuid4())
        if not initial_checkpoint.get("timestamp"):
            initial_checkpoint["timestamp"] = current_time
        
        # Create thread document
        thread_doc = {
            "id": thread_id,
            "title": title,
            "users": users,
            "checkpoints": [initial_checkpoint],
            "status": "active",
            "created_at": current_time,
            "updated_at": current_time,
            "metadata": metadata
        }
        
        # Insert into database
        db.threads.insert_one(thread_doc)
        
        return {"thread_id": thread_id, "status": "created"}
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.post("/threads/{thread_id}/checkpoints")
async def add_checkpoint(
    request: Request,
    thread_id: str,
    checkpoint_data: Dict[str, Any] = Body(...),
):
    """Add a checkpoint to an existing thread"""
    check_rate_limit(request)
    verify_token(checkpoint_data.get("token", ""))
    
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        # Extract checkpoint data
        checkpoint = checkpoint_data.get("checkpoint", {})
        
        # Ensure checkpoint has required fields
        if not checkpoint.get("id"):
            checkpoint["id"] = str(uuid.uuid4())
        if not checkpoint.get("timestamp"):
            checkpoint["timestamp"] = datetime.utcnow().isoformat() + "Z"
        
        # Add checkpoint to thread
        current_time = datetime.utcnow().isoformat() + "Z"
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"checkpoints": checkpoint},
                "$set": {"updated_at": current_time}
            }
        )
        
        return {"status": "checkpoint_added", "checkpoint_id": checkpoint["id"]}
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.post("/threads/{thread_id}/users")
async def join_thread(
    request: Request,
    thread_id: str,
    user_data: Dict[str, Any] = Body(...),
):
    """Add a user to an existing thread"""
    check_rate_limit(request)
    verify_token(user_data.get("token", ""))
    
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        # Extract user data
        user_id = user_data.get("user_id")
        user_name = user_data.get("user_name")
        
        if not user_id or not user_name:
            raise HTTPException(status_code=400, detail="user_id and user_name are required")
        
        # Check if user is already in thread
        existing_users = [u["id"] for u in thread.get("users", [])]
        if user_id in existing_users:
            return {"status": "already_member"}
        
        # Add user to thread
        new_user = {
            "id": user_id,
            "name": user_name,
            "joined_at": datetime.utcnow().isoformat() + "Z"
        }
        
        current_time = datetime.utcnow().isoformat() + "Z"
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"users": new_user},
                "$set": {"updated_at": current_time}
            }
        )
        
        return {"status": "user_added"}
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/threads")
async def get_threads(
    request: Request,
    token: str = Query(..., description="API Token"),
    limit: int = Query(50, description="Number of results"),
    offset: int = Query(0, description="Offset for pagination"),
    user_id: Optional[str] = Query(None, description="Filter by user ID")
):
    """Get threads with optional user filtering"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Build query
        query = {}
        if user_id:
            query["users.id"] = user_id
        
        # Get total count for pagination
        total = db.threads.count_documents(query)
        
        # Get threads with pagination, sorted by updated date (newest first)
        threads_cursor = db.threads.find(
            query, 
            {"_id": 0}
        ).sort("updated_at", -1).limit(limit).skip(offset)
        
        threads_list = list(threads_cursor)
        
        return {
            "threads": threads_list,
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/threads/{thread_id}")
async def get_thread(
    request: Request, 
    thread_id: str, 
    token: str = Query(..., description="API Token")
):
    """Get individual thread data by ID from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        thread = db.threads.find_one({"id": thread_id}, {"_id": 0})
        
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        return thread
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.put("/threads/{thread_id}")
async def update_thread(
    request: Request,
    thread_id: str,
    update_data: Dict[str, Any] = Body(...),
):
    """Update thread metadata"""
    check_rate_limit(request)
    verify_token(update_data.get("token", ""))
    
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        # Build update document
        update_doc = {"updated_at": datetime.utcnow().isoformat() + "Z"}
        
        if "title" in update_data:
            update_doc["title"] = update_data["title"]
        if "status" in update_data:
            update_doc["status"] = update_data["status"]
        if "metadata" in update_data:
            update_doc["metadata"] = update_data["metadata"]
        
        # Update thread
        db.threads.update_one(
            {"id": thread_id},
            {"$set": update_doc}
        )
        
        return {"status": "updated"}
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.delete("/threads/{thread_id}")
async def delete_thread(
    request: Request,
    thread_id: str,
    token: str = Query(..., description="API Token")
):
    """Delete (archive) a thread"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        # Archive the thread instead of deleting
        current_time = datetime.utcnow().isoformat() + "Z"
        db.threads.update_one(
            {"id": thread_id},
            {
                "$set": {
                    "status": "archived",
                    "updated_at": current_time
                }
            }
        )
        
        return {"status": "archived"}
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/threads/stats")
async def get_thread_stats(
    request: Request, 
    token: str = Query(..., description="API Token")
):
    """Get thread statistics from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Get various thread statistics
        total_threads = db.threads.count_documents({})
        active_threads = db.threads.count_documents({"status": "active"})
        archived_threads = db.threads.count_documents({"status": "archived"})
        
        # Get total checkpoints across all threads
        checkpoints_pipeline = [
            {"$project": {"checkpoint_count": {"$size": "$checkpoints"}}},
            {"$group": {"_id": None, "total_checkpoints": {"$sum": "$checkpoint_count"}}}
        ]
        checkpoints_result = list(db.threads.aggregate(checkpoints_pipeline))
        total_checkpoints = checkpoints_result[0]["total_checkpoints"] if checkpoints_result else 0
        
        # Get threads by status
        status_pipeline = [
            {"$group": {"_id": "$status", "count": {"$sum": 1}}}
        ]
        status_result = list(db.threads.aggregate(status_pipeline))
        status_counts = {item["_id"]: item["count"] for item in status_result}
        
        return {
            "thread_stats": {
                "total_threads": total_threads,
                "active_threads": active_threads,
                "archived_threads": archived_threads,
                "total_checkpoints": total_checkpoints,
                "status_breakdown": status_counts
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/threads/search")
async def search_threads(
    request: Request,
    token: str = Query(..., description="API Token"),
    q: str = Query(..., description="Search query"),
    limit: int = Query(20, description="Number of results"),
    offset: int = Query(0, description="Offset for pagination")
):
    """Search threads by title or metadata"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Build search query (text search on title and metadata)
        search_query = {
            "$or": [
                {"title": {"$regex": q, "$options": "i"}},
                {"metadata.description": {"$regex": q, "$options": "i"}},
                {"metadata.tags": {"$in": [q]}},
                {"metadata.genre": {"$regex": q, "$options": "i"}}
            ]
        }
        
        # Get total count for pagination
        total = db.threads.count_documents(search_query)
        
        # Get threads with pagination, sorted by relevance (updated date)
        threads_cursor = db.threads.find(
            search_query, 
            {"_id": 0}
        ).sort("updated_at", -1).limit(limit).skip(offset)
        
        threads_list = list(threads_cursor)
        
        return {
            "threads": threads_list,
            "search_query": q,
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/stats")
async def get_platform_stats(request: Request, token: str = Query(..., description="API Token")):
    """Get platform statistics from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Get various platform statistics
        total_users = db.profiles.count_documents({})
        total_threads = db.threads.count_documents({})
        active_threads = db.threads.count_documents({"status": "active"})
        
        # Get total checkpoints across all threads
        checkpoints_pipeline = [
            {"$project": {"checkpoint_count": {"$size": "$checkpoints"}}},
            {"$group": {"_id": None, "total_checkpoints": {"$sum": "$checkpoint_count"}}}
        ]
        checkpoints_result = list(db.threads.aggregate(checkpoints_pipeline))
        total_checkpoints = checkpoints_result[0]["total_checkpoints"] if checkpoints_result else 0
        
        # Get total collaborations (threads with more than 1 user)
        collaboration_pipeline = [
            {"$project": {"user_count": {"$size": "$users"}}},
            {"$match": {"user_count": {"$gt": 1}}},
            {"$count": "collaborations"}
        ]
        collaboration_result = list(db.threads.aggregate(collaboration_pipeline))
        total_collaborations = collaboration_result[0]["collaborations"] if collaboration_result else 0
        
        return {
            "platform_stats": {
                "total_users": total_users,
                "total_threads": total_threads,
                "active_threads": active_threads,
                "total_checkpoints": total_checkpoints,
                "total_collaborations": total_collaborations
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
