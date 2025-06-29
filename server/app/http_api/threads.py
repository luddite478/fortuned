from fastapi import Request, Body, HTTPException, Query
from http_api.rate_limiter import check_rate_limit
from pymongo import MongoClient
from typing import Dict, Any, Optional
from datetime import datetime
import uuid
import os

MONGO_URL = "mongodb://admin:test@mongodb:27017/admin?authSource=admin"
DATABASE_NAME = "admin"
API_TOKEN = os.getenv("API_TOKEN")

def get_db():
    client = MongoClient(MONGO_URL)
    return client[DATABASE_NAME]

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

async def create_thread_handler(request: Request, thread_data: Dict[str, Any] = Body(...)):
    check_rate_limit(request)
    verify_token(thread_data.get("token", ""))
    try:
        db = get_db()
        thread_id = str(uuid.uuid4())
        now = datetime.utcnow().isoformat() + "Z"
        title = thread_data.get("title", "Untitled Thread")
        users = thread_data.get("users", [])
        initial_checkpoint = thread_data.get("initial_checkpoint")  # Can be None
        metadata = thread_data.get("metadata", {})
        
        # Only process initial checkpoint if provided
        checkpoints = []
        if initial_checkpoint:
            if not initial_checkpoint.get("id"):
                initial_checkpoint["id"] = str(uuid.uuid4())
            if not initial_checkpoint.get("timestamp"):
                initial_checkpoint["timestamp"] = now
            checkpoints = [initial_checkpoint]
        
        thread_doc = {
            "id": thread_id,
            "title": title,
            "users": users,
            "checkpoints": checkpoints,  # Can be empty list
            "status": "active",
            "created_at": now,
            "updated_at": now,
            "metadata": metadata
        }
        
        db.threads.insert_one(thread_doc)
        return {"thread_id": thread_id, "status": "created"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def add_checkpoint_handler(request: Request, thread_id: str, checkpoint_data: Dict[str, Any] = Body(...)):
    check_rate_limit(request)
    verify_token(checkpoint_data.get("token", ""))
    try:
        db = get_db()
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        checkpoint = checkpoint_data.get("checkpoint", {})
        if not checkpoint.get("id"):
            checkpoint["id"] = str(uuid.uuid4())
        if not checkpoint.get("timestamp"):
            checkpoint["timestamp"] = datetime.utcnow().isoformat() + "Z"
        
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"checkpoints": checkpoint},
                "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
            }
        )
        return {"status": "checkpoint_added", "checkpoint_id": checkpoint["id"]}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def join_thread_handler(request: Request, thread_id: str, user_data: Dict[str, Any] = Body(...)):
    check_rate_limit(request)
    verify_token(user_data.get("token", ""))
    try:
        db = get_db()
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        user_id = user_data.get("user_id")
        user_name = user_data.get("user_name")
        if not user_id or not user_name:
            raise HTTPException(status_code=400, detail="user_id and user_name are required")
        
        existing_users = [u["id"] for u in thread.get("users", [])]
        if user_id in existing_users:
            return {"status": "already_member"}
        
        new_user = {
            "id": user_id,
            "name": user_name,
            "joined_at": datetime.utcnow().isoformat() + "Z"
        }
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"users": new_user},
                "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
            }
        )
        return {"status": "user_added"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def get_threads_handler(request: Request, token: str, limit: int = 50, offset: int = 0, user_id: Optional[str] = None):
    check_rate_limit(request)
    verify_token(token)
    try:
        db = get_db()
        # Fix: Only add user_id filter if it's actually provided and not None
        query = {}
        if user_id is not None and user_id.strip():
            query["users.id"] = user_id
            
        total = db.threads.count_documents(query)
        threads_cursor = db.threads.find(query, {"_id": 0}).sort("updated_at", -1).limit(limit).skip(offset)
        return {
            "threads": list(threads_cursor),
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def get_thread_handler(request: Request, thread_id: str, token: str = Query(...)):
    check_rate_limit(request)
    verify_token(token)
    try:
        db = get_db()
        thread = db.threads.find_one({"id": thread_id}, {"_id": 0})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        return thread
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def update_thread_handler(request: Request, thread_id: str, update_data: Dict[str, Any] = Body(...)):
    check_rate_limit(request)
    verify_token(update_data.get("token", ""))
    try:
        db = get_db()
        
        # Check if thread exists first
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        # If there's a checkpoint in the update data, add it to the thread
        if "checkpoint" in update_data:
            checkpoint = update_data.pop("checkpoint")
            db.threads.update_one(
                {"id": thread_id},
                {"$push": {"checkpoints": checkpoint}}
            )
        
        # Update other fields
        update_fields = {k: v for k, v in update_data.items() if k != "token"}
        update_fields["updated_at"] = datetime.utcnow().isoformat() + "Z"
        
        result = db.threads.update_one({"id": thread_id}, {"$set": update_fields})
        
        if result.matched_count == 0:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
            
        return {"status": "updated"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


