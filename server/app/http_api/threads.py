import uuid
import json
import asyncio
from datetime import datetime, timezone
from fastapi import Request, Query, HTTPException, Body
from typing import Optional, Dict, Any, List
import os
from db.connection import get_database
from ws.router import send_thread_invitation_notification, send_message_created_notification, send_invitation_accepted_notification
from bson import ObjectId

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
        thread_id = str(ObjectId())
        now = datetime.utcnow().isoformat() + "Z"
        users = thread_data.get("users", [])

        # Ensure users array items have required fields (id, name, joined_at)
        normalized_users: List[Dict[str, Any]] = []
        for u in users:
            if not isinstance(u, dict):
                continue
            user_id = u.get("id")
            user_name = u.get("name")
            joined_at = u.get("joined_at") or now
            if not user_id or not user_name:
                continue
            normalized_users.append({
                "id": user_id,
                "name": user_name,
                "joined_at": joined_at
            })

        invites = thread_data.get("invites", [])

        thread_doc = {
            "schema_version": 1,
            "id": thread_id,
            "users": normalized_users,
            "messages": [],
            "invites": invites,
            "created_at": now,
            "updated_at": now
        }

        db.threads.insert_one(thread_doc)
        return {"thread_id": thread_id, "status": "created"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def add_checkpoint_handler(request: Request, thread_id: str, checkpoint_data: Dict[str, Any] = Body(...)):
    verify_token(checkpoint_data.get("token", ""))
    # Checkpoints are deprecated in the new schema
    raise HTTPException(status_code=410, detail="Checkpoints are deprecated. Use messages and snapshots instead.")

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
        
        # Allow only schema fields: users, messages, invites
        allowed_fields = {"users", "messages", "invites"}
        provided_fields = set(update_data.keys()) - {"token"}
        unsupported = provided_fields - allowed_fields
        if unsupported:
            raise HTTPException(status_code=400, detail=f"Unsupported fields: {', '.join(sorted(unsupported))}")

        update_fields = {k: v for k, v in update_data.items() if k in allowed_fields}
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
        
        # Add pending invite to the invited user's document
        try:
            db.users.update_one(
                {"id": user_id},
                {"$addToSet": {"pending_invites_to_threads": thread_id}}
            )
        except Exception:
            pass

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
                thread_title=f"Thread {thread_id[:6]}"
            )
        except Exception as e:
            # Don't fail the request if WebSocket notification fails
            print(f"⚠️  Failed to send WebSocket notification: {e}")
        
        return {"status": "invitation_sent"}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

# Messages handlers (store messages in a separate collection with reference, or inline for simplicity)
async def get_messages_handler(request: Request, thread_id: str, token: str, limit: int = 100, order: str = "asc", include_snapshot: bool = True):
    verify_token(token)
    try:
        db = get_db()
        sort_dir = 1 if order == "asc" else -1
        projection = {"_id": 0}
        if not include_snapshot:
            projection["snapshot"] = 0
        cursor = (
            db.messages
            .find({"parent_thread": thread_id}, projection)
            .sort("timestamp", sort_dir)
            .limit(limit)
        )
        return {"messages": list(cursor)}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def get_message_by_id_handler(request: Request, message_id: str, token: str, include_snapshot: bool = True):
    verify_token(token)
    try:
        db = get_db()
        projection = {"_id": 0}
        if not include_snapshot:
            projection["snapshot"] = 0
        doc = db.messages.find_one({"id": message_id}, projection)
        if not doc:
            raise HTTPException(status_code=404, detail=f"Message not found: {message_id}")
        return doc
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def create_message_handler(request: Request, message_data: Dict[str, Any] = Body(...)):
    verify_token(message_data.get("token", ""))
    try:
        db = get_db()
        thread_id = message_data.get("parent_thread")
        user_id = message_data.get("user_id")
        snapshot = message_data.get("snapshot")
        # Explicitly supported optional: snapshot_metadata
        snapshot_metadata = message_data.get("snapshot_metadata")
        timestamp = message_data.get("timestamp") or datetime.utcnow().isoformat() + "Z"
        if not thread_id or not user_id or snapshot is None:
            raise HTTPException(status_code=400, detail="parent_thread, user_id and snapshot are required")

        # ensure thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail=f"Thread not found: {thread_id}")

        message_id = str(ObjectId())
        created_at = datetime.utcnow().isoformat() + "Z"
        doc = {
            "id": message_id,
            "created_at": created_at,
            "timestamp": timestamp,
            "user_id": user_id,
            "parent_thread": thread_id,
            "snapshot": snapshot,
            **({"snapshot_metadata": snapshot_metadata} if snapshot_metadata is not None else {}),
        }
        # Insert a shallow copy so the original doc isn't mutated with Mongo's _id
        db.messages.insert_one({**doc})
        # update thread messages array and updated_at
        db.threads.update_one({"id": thread_id}, {"$push": {"messages": message_id}, "$set": {"updated_at": created_at}})
        # Broadcast realtime notification to thread members (fire-and-forget)
        try:
            asyncio.create_task(send_message_created_notification(thread_id, {**doc}))
        except Exception:
            pass
        # Return the original doc (contains only strings), avoiding ObjectId in response
        return doc
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def delete_message_handler(request: Request, message_id: str, token: str = Query(...)):
    verify_token(token)
    try:
        db = get_db()
        # Find message
        message = db.messages.find_one({"id": message_id})
        if not message:
            raise HTTPException(status_code=404, detail=f"Message not found: {message_id}")
        thread_id = message.get("parent_thread")
        # Delete message document
        db.messages.delete_one({"id": message_id})
        # Remove reference from thread and update timestamp
        if thread_id:
            db.threads.update_one({"id": thread_id}, {"$pull": {"messages": message_id}, "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}})
        return {"status": "deleted", "id": message_id}
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
            # Update user doc: remove pending invite and add thread to user's threads
            try:
                db.users.update_one(
                    {"id": user_id},
                    {
                        "$pull": {"pending_invites_to_threads": thread_id},
                        "$addToSet": {"threads": thread_id}
                    }
                )
            except Exception:
                pass
            # Notify inviter and members
            try:
                invited_by = invitation.get("invited_by")
                asyncio.create_task(send_invitation_accepted_notification(thread_id, user_id, invitation["user_name"], invited_by))
            except Exception:
                pass
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
            # Remove pending invite from user doc
            try:
                db.users.update_one(
                    {"id": user_id},
                    {"$pull": {"pending_invites_to_threads": thread_id}}
                )
            except Exception:
                pass
            return {"status": "invitation_declined"}
    
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


async def delete_thread_handler(request: Request, thread_id: str, token: str = Query(...)):
    """Delete a thread by ID"""
    verify_token(token)
    try:
        db = get_db()
        
        # Check if thread exists
        thread = db.threads.find_one({"id": thread_id})
        if not thread:
            raise HTTPException(status_code=404, detail="Thread not found")
        
        # Delete all messages associated with this thread
        db.messages.delete_many({"parent_thread": thread_id})
        
        # Delete the thread itself
        result = db.threads.delete_one({"id": thread_id})
        
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Thread not found")
        
        return {"status": "thread_deleted", "thread_id": thread_id}
    
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


