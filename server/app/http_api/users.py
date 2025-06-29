import uuid
import bcrypt
import hashlib
from datetime import datetime, timezone
from fastapi import Request, Query, HTTPException
from fastapi.responses import JSONResponse
from typing import Optional, Dict, Any
import os
from http_api.rate_limiter import check_rate_limit
from pymongo import MongoClient
from pydantic import BaseModel

MONGO_URL = "mongodb://admin:test@mongodb:27017/admin?authSource=admin"
DATABASE_NAME = "admin"
API_TOKEN = os.getenv("API_TOKEN")

# Connect to MongoDB
client = MongoClient(MONGO_URL)
db = client[DATABASE_NAME]

# Pydantic models for request/response
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

def get_db():
    return db

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
        
        # Create new user
        user_id = str(uuid.uuid4())
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
            }
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

async def get_user_handler(request: Request, id: str = Query(...), token: str = Query(...)):
    """Get user by ID (renamed from get_user_profile_handler)"""
    try:
        # Validate token (basic check)
        expected_token = "asdfasdasduiu546"
        if token != expected_token:
            raise HTTPException(status_code=401, detail="Invalid API token")

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
        # Validate token (basic check)
        expected_token = "asdfasdasduiu546"
        if token != expected_token:
            raise HTTPException(status_code=401, detail="Invalid API token")

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
