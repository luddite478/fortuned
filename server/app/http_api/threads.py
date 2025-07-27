import uuid
import json
import asyncio
from datetime import datetime, timezone
from fastapi import Request, Query, HTTPException, Body
from typing import Optional, Dict, Any, List
import os
from db.connection import get_database
from ws.router import send_thread_invitation_notification

# Initialize database connection
db = get_database()

API_TOKEN = os.getenv("API_TOKEN")

def get_db():
    return get_database()

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

async def create_thread_handler(request: Request, thread_data: Dict[str, Any] = Body(...)):
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

async def send_invitation_handler(request: Request, thread_id: str, invitation_data: Dict[str, Any] = Body(...)):
    verify_token(invitation_data.get("token", ""))
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        user_id = invitation_data.get("user_id")
        user_name = invitation_data.get("user_name")
        invited_by = invitation_data.get("invited_by")
        
        if not user_id or not user_name or not invited_by:
            raise HTTPException(status_code=400, detail="user_id, user_name, and invited_by are required")
        
        # Check if user is already a member
        existing_users = [u["id"] for u in thread.get("users", [])]
        if user_id in existing_users:
            raise HTTPException(status_code=400, detail="User is already a member of this thread")
        
        # Check if user already has a pending invitation
        existing_invites = thread.get("invites", [])
        for invite in existing_invites:
            if invite.get("user_id") == user_id and invite.get("status") == "pending":
                raise HTTPException(status_code=400, detail="User already has a pending invitation")
        
        # Create new invitation
        invitation = {
            "user_id": user_id,
            "user_name": user_name,
            "status": "pending",
            "invited_by": invited_by,
            "invited_at": datetime.utcnow().isoformat() + "Z"
        }
        
        # Initialize invites array if it doesn't exist, then add invitation
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"invites": invitation},
                "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
            }
        )
        
        # Send WebSocket notification to invited user
        try:
            # Get the name of the person who invited (for the notification)
            inviter = db.users.find_one({"id": invited_by}, {"name": 1, "username": 1})
            inviter_name = inviter.get("name", inviter.get("username", "Unknown")) if inviter else "Unknown"
            
            # Send real-time notification
            await send_thread_invitation_notification(
                target_user_id=user_id,
                from_user_id=invited_by,
                from_user_name=inviter_name,
                thread_id=thread_id,
                thread_title=thread.get("title", "Untitled Thread")
            )
        except Exception as e:
            # Don't fail the request if WebSocket notification fails
            print(f"⚠️  Failed to send WebSocket notification: {e}")
        
        return {"status": "invitation_sent"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def manage_invitation_handler(request: Request, thread_id: str, user_id: str, action_data: Dict[str, Any] = Body(...)):
    verify_token(action_data.get("token", ""))
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")
        
        action = action_data.get("action")
        if action not in ["accept", "decline"]:
            raise HTTPException(status_code=400, detail="Action must be 'accept' or 'decline'")
        
        # Find the invitation
        invites = thread.get("invites", [])
        invitation = None
        invite_index = None
        
        for i, invite in enumerate(invites):
            if invite.get("user_id") == user_id and invite.get("status") == "pending":
                invitation = invite
                invite_index = i
                break
        
        if not invitation:
            raise HTTPException(status_code=404, detail="No pending invitation found for this user")
        
        if action == "accept":
            # Add user to thread members
            new_user = {
                "id": user_id,
                "name": invitation["user_name"],
                "joined_at": datetime.utcnow().isoformat() + "Z"
            }
            
            # Remove invitation and add user in one atomic operation
            db.threads.update_one(
                {"id": thread_id},
                {
                    "$push": {"users": new_user},
                    "$pull": {"invites": {"user_id": user_id}},
                    "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
                }
            )
            return {"status": "invitation_accepted", "user_added": True}
        
        elif action == "decline":
            # Remove invitation
            db.threads.update_one(
                {"id": thread_id},
                {
                    "$pull": {"invites": {"user_id": user_id}},
                    "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
                }
            )
            return {"status": "invitation_declined"}
    
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


