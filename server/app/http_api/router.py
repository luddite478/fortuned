# routes/router.py
from fastapi import APIRouter, Request, Query, HTTPException
from http_api.rate_limiter import check_rate_limit
import json
import os
from typing import Optional
from datetime import datetime
from pymongo import MongoClient

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

@router.get("/projects")
async def get_project(request: Request, id: str = Query(..., description="Project ID"), token: str = Query(..., description="API Token")):
    """Get individual project data by ID from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        project = db.projects.find_one({"id": id}, {"_id": 0})
        
            if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {id}")
    
    return project
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

@router.get("/projects/user")
async def get_user_projects(
    request: Request, 
    user_id: str = Query(..., description="User ID"),
    token: str = Query(..., description="API Token"),
    limit: int = Query(20, description="Number of results"),
    offset: int = Query(0, description="Offset for pagination")
):
    """Get all projects for a specific user with pagination from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
        # Get total count for pagination
        total = db.projects.count_documents({"user_id": user_id})
        
            # Get projects with pagination, sorted by creation date (newest first)
    projects_cursor = db.projects.find(
            {"user_id": user_id}, 
            {"_id": 0}
        ).sort("created", -1).limit(limit).skip(offset)
        
        projects_list = list(projects_cursor)
        
        return {
            "user_id": user_id,
            "projects": projects_list,
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/projects/recent")
async def get_recent_projects(
    request: Request,
    token: str = Query(..., description="API Token"),
    limit: int = Query(20, description="Number of results")
):
    """Get recently created projects across all users from database"""
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        
            # Get recent projects sorted by creation date (newest first)
    recent_cursor = db.projects.find(
            {"visibility": "public"}, 
            {
                "_id": 0,
                "id": 1,
                "user_id": 1,
                "name": 1,
                "plays_num": 1,
                "forks_num": 1,
                "created": 1,
                "tags": 1
            }
        ).sort("created", -1).limit(limit)
        
        recent_list = list(recent_cursor)
        
        return {
            "recent": recent_list,
            "limit": limit,
            "total_results": len(recent_list)
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
        total_projects = db.projects.count_documents({})
        public_projects = db.projects.count_documents({"visibility": "public"})
        
        # Get total plays across all projects
        plays_pipeline = [
            {"$group": {"_id": None, "total_plays": {"$sum": "$plays_num"}}}
        ]
        plays_result = list(db.projects.aggregate(plays_pipeline))
        total_plays = plays_result[0]["total_plays"] if plays_result else 0
        
        # Get total forks across all projects
        forks_pipeline = [
            {"$group": {"_id": None, "total_forks": {"$sum": "$forks_num"}}}
        ]
        forks_result = list(db.projects.aggregate(forks_pipeline))
        total_forks = forks_result[0]["total_forks"] if forks_result else 0
        
        return {
            "platform_stats": {
                "total_users": total_users,
                        "total_projects": total_projects,
        "public_projects": public_projects,
                "total_plays": total_plays,
                "total_forks": total_forks
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
