import uuid
import bcrypt
import hashlib
from datetime import datetime, timezone
from fastapi import Request, Query, HTTPException
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder
from typing import Optional, Dict, Any, List
import os
from pymongo import MongoClient
from pydantic import BaseModel, Field
from db.connection import get_database
from bson import ObjectId

# Initialize database connection
db = get_database()

API_TOKEN = os.getenv("API_TOKEN")

# Pydantic models for request/response
class UserProfileInfo(BaseModel):
    bio: str
    location: str

class UserStats(BaseModel):
    total_plays: int

class UserPreferences(BaseModel):
    theme: str

class PlaylistItem(BaseModel):
    name: str
    url: str
    id: str
    format: str
    bitrate: Optional[int] = None
    duration: Optional[float] = None
    size_bytes: Optional[int] = Field(None, alias='sizeBytes')
    created_at: str
    type: str

class UserSessionRequest(BaseModel):
    id: str
    username: str
    name: str
    email: str
    created_at: str
    last_login: str
    last_online: str
    is_active: bool
    email_verified: bool
    profile: UserProfileInfo
    stats: UserStats
    preferences: UserPreferences
    threads: List[str] = []
    pending_invites_to_threads: List[str] = []
    playlist: List[PlaylistItem] = []

class LoginRequest(BaseModel):
    email: str
    password: str

class RegisterRequest(BaseModel):
    username: str
    name: str
    email: str
    password: str

class LoginResponse(BaseModel):
    success: bool
    user_id: Optional[str] = None
    username: Optional[str] = None
    name: Optional[str] = None
    email: Optional[str] = None
    message: Optional[str] = None

class FollowRequest(BaseModel):
    user_id: str
    target_user_id: str

def get_db():
    return get_database()

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

# Authentication functions
def hash_password(password: str) -> tuple[str, str]:
    """Hash password with bcrypt and return hash and salt"""
    salt = bcrypt.gensalt()
    password_hash = bcrypt.hashpw(password.encode('utf-8'), salt)
    return password_hash.decode('utf-8'), salt.decode('utf-8')

def verify_password(password: str, hashed: str) -> bool:
    """Verify password against hash"""
    return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))

# API Endpoints
async def login_handler(request: Request, login_data: LoginRequest):
    """Authenticate user with email and password"""
    try:
        # Find user by email
        user = db.users.find_one({"email": login_data.email}, {"_id": 0})
        
        if not user:
            raise HTTPException(status_code=401, detail="Invalid email or password")
        
        # Verify password
        if not verify_password(login_data.password, user['password_hash']):
            raise HTTPException(status_code=401, detail="Invalid email or password")
        
        # Check if user is active
        if not user.get('is_active', True):
            raise HTTPException(status_code=403, detail="Account is deactivated")
        
        # IDs are now seeded as Mongo 24-hex in init; no migration at login

        # Update last login
        db.users.update_one(
            {"id": user['id']},
            {"$set": {"last_login": datetime.now(timezone.utc).isoformat()}}
        )
        
        return LoginResponse(
            success=True,
            user_id=user['id'],
            username=user['username'],
            name=user['name'],
            email=user['email'],
            message="Login successful"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Login failed: {str(e)}")

async def register_handler(request: Request, register_data: RegisterRequest):
    """Register new user"""
    try:
        # Check if email already exists
        existing_email = db.users.find_one({"email": register_data.email})
        if existing_email:
            raise HTTPException(status_code=400, detail="Email already registered")
        
        # Check if username already exists
        existing_username = db.users.find_one({"username": register_data.username})
        if existing_username:
            raise HTTPException(status_code=400, detail="Username already taken")
        
        # Hash password
        password_hash, salt = hash_password(register_data.password)
        
        # Create new user (Mongo-style 24-hex ID)
        user_id = str(ObjectId())
        new_user = {
            "id": user_id,
            "username": register_data.username,
            "name": register_data.name,
            "email": register_data.email,
            "password_hash": password_hash,
            "salt": salt,
            "profile": {
                "bio": "",
                "location": ""
            },
            "created_at": datetime.now(timezone.utc).isoformat(),
            "last_login": datetime.now(timezone.utc).isoformat(),
            "last_online": datetime.now(timezone.utc).isoformat(),
            "is_active": True,
            "email_verified": False,
            "stats": {
                "total_plays": 0
            },
            "preferences": {
                "theme": "dark"
            },
            "following": []
        }
        
        # Insert user
        db.users.insert_one(new_user)
        
        return LoginResponse(
            success=True,
            user_id=user_id,
            username=register_data.username,
            name=register_data.name,
            email=register_data.email,
            message="Registration successful"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

async def session_handler(request: Request, user_data: UserSessionRequest):
    """Get or create a user session for anonymous, device-based authentication."""
    try:
        # Find user by ID (exclude MongoDB's _id field)
        existing_user = db.users.find_one({"id": user_data.id}, {"_id": 0})
        
        if existing_user:
            # User exists, update last_online and return
            db.users.update_one(
                {"id": user_data.id},
                {"$set": {"last_online": datetime.now(timezone.utc).isoformat()}}
            )
            # Return the user data (already has _id excluded)
            return JSONResponse(content=existing_user)
        
        else:
            # User doesn't exist, create a new one from the client-provided data
            new_user_doc = user_data.dict(by_alias=True)
            
            # Ensure required fields for a new user are present, even if not sent
            new_user_doc.setdefault("following", [])
            
            # We don't want to store password info for anonymous users
            new_user_doc.pop("password_hash", None)
            new_user_doc.pop("salt", None)
            
            db.users.insert_one(new_user_doc)
            
            # Remove the MongoDB _id field before returning
            new_user_doc.pop("_id", None)
            
            return JSONResponse(content=new_user_doc, status_code=201)
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session handling failed: {str(e)}")

async def get_user_handler(request: Request, id: str = Query(...), token: str = Query(...)):
    """Get user by ID (renamed from get_user_profile_handler)"""
    try:
        # Validate token using environment variable
        verify_token(token)

        user = db.users.find_one({"id": id}, {"_id": 0, "password_hash": 0, "salt": 0})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {id}")
        return user

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get user: {str(e)}")

async def get_users_handler(request: Request, token: str = Query(...), limit: int = Query(20), offset: int = Query(0)):
    """Get list of users (renamed from get_user_profiles_handler)"""
    try:
        # Validate token using environment variable
        verify_token(token)

        total = db.users.count_documents({})
        users_cursor = db.users.find(
            {}, 
            {"_id": 0, "password_hash": 0, "salt": 0}
        ).skip(offset).limit(limit)

        users_list = list(users_cursor)
        
        has_more = offset + limit < total

        return {
            "users": users_list,
            "pagination": {
                "total": total,
                "limit": limit,
                "offset": offset,
                "has_more": has_more
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get users: {str(e)}")

async def follow_user_handler(request: Request, follow_data: Dict[str, Any]):
    """Follow a user"""
    try:
        verify_token(follow_data.get("token", ""))
        
        user_id = follow_data.get("user_id")
        target_user_id = follow_data.get("target_user_id")
        
        # Check if both users exist
        user = db.users.find_one({"id": user_id})
        target_user = db.users.find_one({"id": target_user_id})
        
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        if not target_user:
            raise HTTPException(status_code=404, detail=f"Target user not found: {target_user_id}")
        
        # Check if already following
        following = user.get("following", [])
        if any(f["user_id"] == target_user_id for f in following):
            return {"success": True, "message": "Already following this user"}
        
        # Add to following list
        following_entry = {
            "user_id": target_user_id,
            "username": target_user["username"]
        }
        
        db.users.update_one(
            {"id": user_id},
            {"$push": {"following": following_entry}}
        )
        
        return {"success": True, "message": "User followed successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to follow user: {str(e)}")

async def unfollow_user_handler(request: Request, follow_data: Dict[str, Any]):
    """Unfollow a user"""
    try:
        verify_token(follow_data.get("token", ""))
        
        user_id = follow_data.get("user_id")
        target_user_id = follow_data.get("target_user_id")
        
        # Check if user exists
        user = db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        # Remove from following list
        db.users.update_one(
            {"id": user_id},
            {"$pull": {"following": {"user_id": target_user_id}}}
        )
        
        return {"success": True, "message": "User unfollowed successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to unfollow user: {str(e)}")

async def search_users_handler(request: Request, token: str = Query(...), query: str = Query(...), limit: int = Query(20)):
    """Search users by username"""
    try:
        verify_token(token)
        
        # Search users by username (case-insensitive)
        search_filter = {
            "username": {"$regex": query, "$options": "i"}
        }
        
        users_cursor = db.users.find(
            search_filter,
            {"_id": 0, "password_hash": 0, "salt": 0}
        ).limit(limit)
        
        users_list = list(users_cursor)
        
        return {
            "users": users_list,
            "query": query,
            "count": len(users_list)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to search users: {str(e)}")

async def get_followed_users_handler(request: Request, token: str = Query(...), user_id: str = Query(...)):
    """Get users followed by a specific user"""
    try:
        verify_token(token)
        
        # Get user with following list
        user = db.users.find_one({"id": user_id}, {"following": 1})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        following = user.get("following", [])
        followed_user_ids = [f["user_id"] for f in following]
        
        if not followed_user_ids:
            return {"users": [], "count": 0}
        
        # Get full user data for followed users
        followed_users_cursor = db.users.find(
            {"id": {"$in": followed_user_ids}},
            {"_id": 0, "password_hash": 0, "salt": 0}
        )
        
        followed_users = list(followed_users_cursor)
        
        return {
            "users": followed_users,
            "count": len(followed_users)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get followed users: {str(e)}")

async def add_to_playlist_handler(request: Request, playlist_data: Dict[str, Any]):
    """Add a render to user's playlist"""
    try:
        verify_token(playlist_data.get("token", ""))
        
        user_id = playlist_data.get("user_id")
        render = playlist_data.get("render")
        
        if not user_id or not render:
            raise HTTPException(status_code=400, detail="Missing user_id or render data")
        
        # Check if user exists
        user = db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        # Check if render already in playlist (prevent duplicates)
        playlist = user.get("playlist", [])
        if any(item["id"] == render["id"] for item in playlist):
            return {"success": True, "message": "Render already in playlist"}
        
        # Add type field
        render["type"] = "render"
        
        # Add to playlist
        db.users.update_one(
            {"id": user_id},
            {"$push": {"playlist": render}}
        )
        
        return {"success": True, "message": "Added to playlist"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to add to playlist: {str(e)}")

async def remove_from_playlist_handler(request: Request, playlist_data: Dict[str, Any]):
    """Remove a render from user's playlist"""
    try:
        verify_token(playlist_data.get("token", ""))
        
        user_id = playlist_data.get("user_id")
        render_id = playlist_data.get("render_id")
        
        if not user_id or not render_id:
            raise HTTPException(status_code=400, detail="Missing user_id or render_id")
        
        # Check if user exists
        user = db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        # Remove from playlist
        db.users.update_one(
            {"id": user_id},
            {"$pull": {"playlist": {"id": render_id}}}
        )
        
        return {"success": True, "message": "Removed from playlist"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to remove from playlist: {str(e)}")

async def get_playlist_handler(request: Request, token: str = Query(...), user_id: str = Query(...)):
    """Get user's playlist"""
    try:
        verify_token(token)
        
        # Get user with playlist
        user = db.users.find_one({"id": user_id}, {"playlist": 1})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        playlist = user.get("playlist", [])
        
        return {
            "playlist": playlist,
            "count": len(playlist)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get playlist: {str(e)}")

class UpdateUsernameRequest(BaseModel):
    username: str

async def update_username_handler(request: Request, user_id: str, username_data: UpdateUsernameRequest):
    """Update user's username"""
    try:
        username = username_data.username.strip()
        
        # Validate username format: min 3 chars, alphanumeric + underscore + hyphen
        if len(username) < 3:
            raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
        
        import re
        if not re.match(r'^[a-zA-Z0-9_-]+$', username):
            raise HTTPException(status_code=400, detail="Username can only contain letters, numbers, underscores, and hyphens")
        
        # Check if user exists
        user = db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=404, detail=f"User not found: {user_id}")
        
        # Update username in users collection (source of truth)
        db.users.update_one(
            {"id": user_id},
            {"$set": {
                "username": username,
                "name": username,  # Also update name to match username
                "last_online": datetime.now(timezone.utc).isoformat()
            }}
        )
        
        # Sync username to all threads where this user is a participant (denormalized copies)
        try:
            result = db.threads.update_many(
                {"users.id": user_id},  # Find all threads with this user
                {"$set": {
                    "users.$[elem].username": username,  # Update embedded username
                    "users.$[elem].name": username  # Update embedded name
                }},
                array_filters=[{"elem.id": user_id}]  # MongoDB array update syntax
            )
            logger.info(f"Updated username in {result.modified_count} thread(s) for user {user_id}")
        except Exception as e:
            logger.error(f"Failed to sync username to threads: {e}")
            # Don't fail the request if thread sync fails
        
        # Broadcast username update to online collaborators via WebSocket
        try:
            from ws.router import send_user_profile_updated_notification
            import asyncio
            delivered = await send_user_profile_updated_notification(user_id, username)
            logger.info(f"Broadcasted username update to {delivered} online user(s)")
        except Exception as e:
            logger.warning(f"Failed to broadcast username update: {e}")
            # Don't fail the request if WebSocket broadcast fails
        
        # Return updated user (exclude sensitive fields)
        updated_user = db.users.find_one({"id": user_id}, {"_id": 0, "password_hash": 0, "salt": 0})
        return JSONResponse(content=updated_user, status_code=200)
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update username: {str(e)}")
