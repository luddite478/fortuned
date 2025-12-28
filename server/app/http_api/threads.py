import uuid
import json
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import Request, Query, HTTPException, Body
from typing import Optional, Dict, Any, List
import os
from db.connection import get_database
from ws.router import send_thread_invitation_notification, send_message_created_notification, send_invitation_accepted_notification
from bson import ObjectId

logger = logging.getLogger(__name__)

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
        name = thread_data.get("name")

        # Ensure users array items have required fields (id, username, name, joined_at)
        # Fetch username from users collection if not provided
        normalized_users: List[Dict[str, Any]] = []
        for u in users:
            if not isinstance(u, dict):
                continue
            user_id = u.get("id")
            user_name = u.get("name")
            username = u.get("username")
            joined_at = u.get("joined_at") or now
            
            # Fetch username from users collection if not provided
            if not username and user_id:
                user_doc = db.users.find_one({"id": user_id}, {"username": 1, "name": 1})
                if user_doc:
                    username = user_doc.get("username", "")
                    if not user_name:
                        user_name = user_doc.get("name", "")
            
            # Allow empty username, but require fields to be present
            if user_id is None or user_name is None:
                continue
            if not user_id:  # user_id cannot be empty
                continue
            # Get user's last_online from users collection
            user_doc = db.users.find_one({"id": user_id}, {"last_online": 1})
            last_online = user_doc.get("last_online") if user_doc else now
            
            normalized_users.append({
                "id": user_id,
                "username": username or user_name,  # Fallback to name if username empty
                "name": user_name,
                "joined_at": joined_at,
                "last_online": last_online
            })

        invites = thread_data.get("invites", [])

        thread_doc = {
            "schema_version": 1,
            "id": thread_id,
            "name": name,
            "users": normalized_users,
            "messages": [],
            "invites": invites,
            "created_at": now,
            "updated_at": now
        }

        db.threads.insert_one(thread_doc)
        
        # Update each user's threads array
        for user in normalized_users:
            user_id = user.get("id")
            if user_id:
                db.users.update_one(
                    {"id": user_id},
                    {"$addToSet": {"threads": thread_id}}  # $addToSet prevents duplicates
                )
        
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
        # Allow empty username (anonymous users), but require the fields to be present
        if user_id is None or user_name is None:
            raise HTTPException(status_code=400, detail="user_id and user_name are required")
        if not user_id:
            raise HTTPException(status_code=400, detail="user_id cannot be empty")
        
        # Fetch username from users collection
        user_doc = db.users.find_one({"id": user_id}, {"username": 1, "name": 1})
        username = user_doc.get("username", user_name) if user_doc else user_name
        display_name = user_doc.get("name", user_name) if user_doc else user_name
        
        existing_users = [u["id"] for u in thread.get("users", [])]
        if user_id in existing_users:
            return {"status": "already_member"}
        
        # Handle username collision by adding number suffix if needed
        existing_usernames = [u.get("username", u.get("name")) for u in thread.get("users", [])]
        final_username = username
        
        if username in existing_usernames:
            # Username collision detected, find a unique suffix
            counter = 1
            while f"{username}_{counter}" in existing_usernames:
                counter += 1
            final_username = f"{username}_{counter}"
            print(f"Username collision detected. Changed '{username}' to '{final_username}'")
        
        # Get user's last_online from users collection
        user_last_online = user_doc.get("last_online", datetime.utcnow().isoformat() + "Z")
        
        new_user = {
            "id": user_id,
            "username": final_username,
            "name": display_name,
            "joined_at": datetime.utcnow().isoformat() + "Z",
            "last_online": user_last_online
        }
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"users": new_user},
                "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}
            }
        )
        
        # Update the user's threads array
        db.users.update_one(
            {"id": user_id},
            {"$addToSet": {"threads": thread_id}}  # $addToSet prevents duplicates
        )
        
        # Also update the user's username in the users collection if it was modified
        if final_username != username:
            db.users.update_one(
                {"id": user_id},
                {"$set": {
                    "username": final_username
                }}
            )
        
        return {
            "status": "user_added",
            "username": final_username  # Return the final username (possibly modified)
        }
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
        # Explicitly supported optional: snapshot_metadata, renders
        snapshot_metadata = message_data.get("snapshot_metadata")
        renders = message_data.get("renders", [])
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
            "renders": renders,
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
        from storage.s3_service import get_s3_service
        import re
        
        db = get_db()
        # Find message
        message = db.messages.find_one({"id": message_id})
        if not message:
            raise HTTPException(status_code=404, detail=f"Message not found: {message_id}")
        
        thread_id = message.get("parent_thread")
        
        # Delete associated render files from S3
        renders = message.get("renders", [])
        if renders:
            s3_service = get_s3_service()
            for render in renders:
                try:
                    render_url = render.get("url", "")
                    if render_url:
                        # Extract file key from URL
                        # URL format: https://fortuned.fra1.digitaloceanspaces.com/prod/renders/uuid.mp3
                        # We need: prod/renders/uuid.mp3
                        match = re.search(r'\.com/(.+)$', render_url)
                        if match:
                            file_key = match.group(1)
                            deleted = s3_service.delete_file(file_key)
                            if deleted:
                                logger.info(f"🗑️  Deleted render from S3: {file_key}")
                            else:
                                logger.warning(f"⚠️  Failed to delete render from S3: {file_key}")
                except Exception as e:
                    # Don't fail message deletion if S3 deletion fails
                    logger.error(f"❌ Error deleting render from S3: {e}")
        
        # Delete message document
        db.messages.delete_one({"id": message_id})
        
        # Remove reference from thread and update timestamp
        if thread_id:
            db.threads.update_one({"id": thread_id}, {"$pull": {"messages": message_id}, "$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}})
        
        return {"status": "deleted", "id": message_id, "renders_deleted": len(renders)}
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def attach_render_to_message_handler(request: Request, message_id: str, render_data: Dict[str, Any] = Body(...)):
    """Attach a render to an existing message (for background upload completion)"""
    verify_token(render_data.get("token", ""))
    try:
        db = get_db()
        # Find message
        message = db.messages.find_one({"id": message_id})
        if not message:
            raise HTTPException(status_code=404, detail=f"Message not found: {message_id}")
        
        # Get render from request
        render = render_data.get("render")
        if not render:
            raise HTTPException(status_code=400, detail="render is required")
        
        # Add render to message
        db.messages.update_one(
            {"id": message_id},
            {"$push": {"renders": render}}
        )
        
        # Update thread timestamp
        thread_id = message.get("parent_thread")
        if thread_id:
            db.threads.update_one(
                {"id": thread_id},
                {"$set": {"updated_at": datetime.utcnow().isoformat() + "Z"}}
            )
        
        return {"status": "render_attached", "message_id": message_id}
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
            # Get user's current last_online status
            user_doc = db.users.find_one({"id": user_id}, {"username": 1, "last_online": 1})
            user_last_online = user_doc.get("last_online", datetime.utcnow().isoformat() + "Z") if user_doc else datetime.utcnow().isoformat() + "Z"
            username = user_doc.get("username", invitation["user_name"]) if user_doc else invitation["user_name"]
            
            new_user = {
                "id": user_id,
                "username": username,
                "name": invitation["user_name"],
                "joined_at": datetime.utcnow().isoformat() + "Z",
                "last_online": user_last_online
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
        
        # Get all users in the thread before deleting
        thread_users = [u.get("id") for u in thread.get("users", [])]
        
        # Delete all messages associated with this thread
        db.messages.delete_many({"parent_thread": thread_id})
        
        # Delete the thread itself
        result = db.threads.delete_one({"id": thread_id})
        
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Thread not found")
        
        # Remove thread from all users' threads arrays
        for user_id in thread_users:
            if user_id:
                db.users.update_one(
                    {"id": user_id},
                    {"$pull": {"threads": thread_id}}
                )
        
        return {"status": "thread_deleted", "thread_id": thread_id}
    
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


