"""
Audio Files API
Handles:
- Audio upload to S3 (content-based addressing)
- Audio file deduplication and reference tracking
- Metadata management
"""

import hashlib
import os
import logging
from datetime import datetime
from fastapi import Request, Query, HTTPException, Body, UploadFile, File, Form
from typing import Optional, Dict, Any
from bson import ObjectId
from db.connection import get_database
from storage.s3_service import get_s3_service

logger = logging.getLogger(__name__)

API_TOKEN = os.getenv("API_TOKEN")

def get_db():
    return get_database()

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")


# =============================================================================
# UPLOAD HANDLER
# =============================================================================

async def upload_audio_handler(
    request: Request,
    file: UploadFile = File(...),
    token: str = Form(...),
    format: str = Form("mp3"),
    bitrate: Optional[int] = Form(None),
    duration: Optional[float] = Form(None),
):
    """
    Upload audio file with content-based addressing
    
    Flow:
    1. Read file content
    2. Calculate SHA-256 hash
    3. Use hash as S3 key: prod/audio/{hash}.{format}
    4. Check if already exists in S3
    5. If exists: return existing URL (deduplication!)
    6. If not: upload to S3
    """
    verify_token(token)
    
    try:
        # Read file content
        file_data = await file.read()
        file_size = len(file_data)
        
        # Calculate content hash (SHA-256)
        content_hash = hashlib.sha256(file_data).hexdigest()
        
        # Construct S3 key using hash (new path structure)
        env = os.getenv("ENV", "prod")  # prod or stage
        s3_key = f"{env}/audio/{content_hash}.{format}"
        
        # Get S3 service
        s3_service = get_s3_service()
        s3_url = s3_service.get_public_url(s3_key)
        
        # Check if file already exists in S3
        if s3_service.file_exists(s3_key):
            logger.info(f"♻️  Audio already exists in S3: {s3_key}")
            
            # Check if audio_files record exists
            db = get_database()
            audio = db.audio_files.find_one({"content_hash": content_hash})
            
            if audio:
                # Perfect - both S3 and DB exist
                logger.info(f"✅ Audio found in DB: {audio['id']}")
                return {
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "audio_file_id": audio["id"],
                    "size_bytes": file_size,
                    "format": format,
                    "status": "existing",
                    "message": "File already exists (content-based deduplication)"
                }
            else:
                # S3 exists but no DB record - create it
                # (This can happen if previous upload succeeded but DB insert failed)
                audio_id = str(ObjectId())
                audio_file = {
                    "schema_version": 1,
                    "id": audio_id,
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "format": format,
                    "reference_count": 0,
                    "size_bytes": file_size,
                    "created_at": datetime.utcnow().isoformat() + "Z"
                }
                
                if bitrate:
                    audio_file["bitrate"] = bitrate
                if duration:
                    audio_file["duration"] = duration
                
                db.audio_files.insert_one(audio_file)
                
                logger.info(f"🔧 Created missing DB record: {audio_id}")
                return {
                    "url": s3_url,
                    "s3_key": s3_key,
                    "content_hash": content_hash,
                    "audio_file_id": audio_id,
                    "size_bytes": file_size,
                    "format": format,
                    "status": "restored",
                    "message": "File existed in S3, DB record created"
                }
        
        # File doesn't exist - upload to S3
        content_type_map = {
            "mp3": "audio/mpeg",
            "wav": "audio/wav",
            "m4a": "audio/mp4",
        }
        content_type = content_type_map.get(format, "audio/mpeg")
        
        uploaded_url = s3_service.upload_file(
            file_content=file_data,
            s3_key=s3_key,
            content_type=content_type
        )
        
        if not uploaded_url:
            raise HTTPException(status_code=500, detail="Failed to upload file to storage")
        
        logger.info(f"✅ Uploaded to S3: {s3_key}")
        
        # Return upload result (client will call POST /audio to register)
        return {
            "url": uploaded_url,
            "s3_key": s3_key,
            "content_hash": content_hash,
            "size_bytes": file_size,
            "format": format,
            "status": "uploaded",
            "message": "File uploaded successfully"
        }
        
    except Exception as e:
        logger.error(f"❌ Upload failed: {e}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


# =============================================================================
# METADATA HANDLERS
# =============================================================================

async def get_audio_file_handler(request: Request, audio_id: str, token: str = Query(...)):
    """
    Get audio file metadata by ID
    """
    verify_token(token)
    try:
        db = get_db()
        audio = db.audio_files.find_one({"id": audio_id}, {"_id": 0})
        if not audio:
            raise HTTPException(status_code=404, detail=f"Audio file not found: {audio_id}")
        return audio
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


async def get_or_create_audio_handler(request: Request, audio_data: Dict[str, Any] = Body(...)):
    """
    Get existing audio file by content_hash/URL, or create new one if doesn't exist
    
    This is the main endpoint used by:
    - Message render upload (no name)
    - Library item addition (with name)
    
    Request body:
    {
      "token": "...",
      "url": "https://s3.../file.mp3",
      "s3_key": "prod/audio/hash.mp3",
      "content_hash": "a1b2c3d4e5f6...",
      "format": "mp3",
      "bitrate": 320,
      "duration": 120.5,
      "size_bytes": 5242880,
      "name": "My Track" (optional, for library items)
    }
    
    Response:
    {
      "id": "audio_file_id",
      "status": "created" | "existing",
      "audio": { full audio object }
    }
    """
    verify_token(audio_data.get("token", ""))
    try:
        db = get_db()
        url = audio_data.get("url")
        content_hash = audio_data.get("content_hash")
        
        if not url:
            raise HTTPException(status_code=400, detail="url is required")
        
        # Try to find by content_hash first (most reliable for deduplication)
        existing = None
        if content_hash:
            existing = db.audio_files.find_one({"content_hash": content_hash}, {"_id": 0})
            if existing:
                logger.info(f"✅ Found audio by hash: {existing['id']}")
        
        # Fallback to URL lookup (backward compatibility)
        if not existing:
            existing = db.audio_files.find_one({"url": url}, {"_id": 0})
            if existing:
                logger.info(f"✅ Found audio by URL: {existing['id']}")
        
        if existing:
            # Increment reference count
            db.audio_files.update_one(
                {"id": existing["id"]},
                {"$inc": {"reference_count": 1}}
            )
            
            # Update name if provided and not already set
            name = audio_data.get("name")
            if name and not existing.get("name"):
                db.audio_files.update_one(
                    {"id": existing["id"]},
                    {"$set": {"name": name}}
                )
                existing["name"] = name
            
            # Get updated document
            updated = db.audio_files.find_one({"id": existing["id"]}, {"_id": 0})
            
            return {
                "id": existing["id"],
                "status": "existing",
                "audio": updated or existing
            }
        
        # Create new audio file record
        audio_id = str(ObjectId())
        audio_file = {
            "schema_version": 1,
            "id": audio_id,
            "url": url,
            "s3_key": audio_data.get("s3_key", ""),
            "content_hash": content_hash or "",
            "format": audio_data.get("format", "mp3"),
            "reference_count": 1,
            "created_at": datetime.utcnow().isoformat() + "Z"
        }
        
        # Add optional fields if provided
        if audio_data.get("name"):
            audio_file["name"] = audio_data["name"]
        if audio_data.get("bitrate"):
            audio_file["bitrate"] = audio_data["bitrate"]
        if audio_data.get("duration"):
            audio_file["duration"] = audio_data["duration"]
        if audio_data.get("size_bytes"):
            audio_file["size_bytes"] = audio_data["size_bytes"]
        
        db.audio_files.insert_one(audio_file)
        
        # Remove MongoDB's _id before returning
        audio_file.pop("_id", None)
        
        logger.info(f"✅ Created new audio record: {audio_id}")
        
        return {
            "id": audio_id,
            "status": "created",
            "audio": audio_file
        }
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


async def decrement_audio_reference_handler(request: Request, audio_data: Dict[str, Any] = Body(...)):
    """
    Decrement reference count for an audio file
    Called when:
    - Message is deleted
    - Library item is removed
    
    AGGRESSIVE DELETION: If reference count reaches 0, deletes from S3 immediately
    
    Request body:
    {
      "token": "...",
      "audio_id": "64c0a6f4e5b1a2c3d4e5f601"
    }
    """
    verify_token(audio_data.get("token", ""))
    try:
        db = get_db()
        s3_service = get_s3_service()
        audio_id = audio_data.get("audio_id")
        
        if not audio_id:
            raise HTTPException(status_code=400, detail="audio_id is required")
        
        # Find the audio file
        audio = db.audio_files.find_one({"id": audio_id})
        if not audio:
            raise HTTPException(status_code=404, detail=f"Audio file not found: {audio_id}")
        
        # Decrement reference count (but not below 0)
        new_count = max(0, audio.get("reference_count", 1) - 1)
        
        if new_count == 0:
            # AGGRESSIVE: Delete from S3 immediately when unreferenced
            try:
                s3_deleted = s3_service.delete_file(audio["s3_key"])
                
                if s3_deleted:
                    # Delete from database
                    db.audio_files.delete_one({"id": audio_id})
                    logger.info(f"🗑️ Deleted unreferenced audio: {audio_id} ({audio['url']})")
                    
                    return {
                        "id": audio_id,
                        "reference_count": 0,
                        "status": "deleted",
                        "message": "Audio deleted from S3 (no references)"
                    }
                else:
                    # S3 delete failed - mark for retry
                    db.audio_files.update_one(
                        {"id": audio_id},
                        {"$set": {"reference_count": 0, "pending_deletion": True}}
                    )
                    logger.warning(f"⚠️ S3 delete failed for {audio_id}, marked for retry")
                    
                    return {
                        "id": audio_id,
                        "reference_count": 0,
                        "status": "pending_deletion",
                        "message": "S3 deletion pending retry"
                    }
                    
            except Exception as e:
                # S3 error - mark for retry
                logger.error(f"❌ Error deleting audio from S3: {e}")
                db.audio_files.update_one(
                    {"id": audio_id},
                    {"$set": {"reference_count": 0, "pending_deletion": True}}
                )
                
                return {
                    "id": audio_id,
                    "reference_count": 0,
                    "status": "pending_deletion",
                    "message": f"S3 deletion failed: {str(e)}"
                }
        else:
            # Still referenced - just decrement
            db.audio_files.update_one(
                {"id": audio_id},
                {"$set": {"reference_count": new_count}}
            )
            
            return {
                "id": audio_id,
                "reference_count": new_count,
                "status": "decremented"
            }
        
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


async def get_audio_stats_handler(request: Request, token: str = Query(...)):
    """
    Get statistics about audio files
    Useful for monitoring storage and deduplication
    
    Returns:
    {
      "total_files": 150,
      "total_references": 300,
      "deduplication_ratio": 2.0,
      "total_size_bytes": 524288000,
      "unreferenced_count": 5
    }
    """
    verify_token(token)
    try:
        db = get_db()
        
        # Count total files
        total_files = db.audio_files.count_documents({})
        
        # Sum all reference counts
        pipeline = [
            {"$group": {
                "_id": None,
                "total_references": {"$sum": "$reference_count"},
                "total_size": {"$sum": "$size_bytes"},
                "unreferenced": {
                    "$sum": {"$cond": [{"$eq": ["$reference_count", 0]}, 1, 0]}
                }
            }}
        ]
        
        result = list(db.audio_files.aggregate(pipeline))
        
        if result:
            stats = result[0]
            total_references = stats.get("total_references", 0)
            deduplication_ratio = total_references / total_files if total_files > 0 else 0
            
            return {
                "total_files": total_files,
                "total_references": total_references,
                "deduplication_ratio": round(deduplication_ratio, 2),
                "total_size_bytes": stats.get("total_size", 0),
                "unreferenced_count": stats.get("unreferenced", 0)
            }
        
        return {
            "total_files": total_files,
            "total_references": 0,
            "deduplication_ratio": 0,
            "total_size_bytes": 0,
            "unreferenced_count": 0
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

