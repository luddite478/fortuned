from fastapi import Request, Query, HTTPException
from typing import Optional
from http_api.rate_limiter import check_rate_limit
from pymongo import MongoClient

MONGO_URL = "mongodb://admin:test@mongodb:27017/admin?authSource=admin"
DATABASE_NAME = "admin"
API_TOKEN = "asdfasdasduiu546"

def get_db():
    client = MongoClient(MONGO_URL)
    return client[DATABASE_NAME]

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

async def get_user_profile_handler(request: Request, id: str = Query(...), token: str = Query(...)):
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

async def get_user_profiles_handler(request: Request, token: str = Query(...), limit: int = Query(20), offset: int = Query(0)):
    check_rate_limit(request)
    verify_token(token)
    
    try:
        db = get_db()
        total = db.profiles.count_documents({})
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
        
        return {
            "profiles": list(users_cursor),
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total,
                "has_more": (offset + limit) < total
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
