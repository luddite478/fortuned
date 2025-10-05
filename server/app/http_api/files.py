"""File upload handlers"""
import uuid
import os
from datetime import datetime
from fastapi import Request, HTTPException, UploadFile, File, Form
from typing import Optional
import logging
from storage.s3_service import get_s3_service

logger = logging.getLogger(__name__)

API_TOKEN = os.getenv("API_TOKEN")

def verify_token(token: str):
    if token != API_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

async def upload_audio_handler(
    request: Request,
    file: UploadFile = File(...),
    token: str = Form(...),
    format: str = Form("mp3"),
    bitrate: Optional[int] = Form(None),
    duration: Optional[float] = Form(None),
):
    """Upload an audio file to S3 storage"""
    verify_token(token)
    
    try:
        # Read file data
        file_data = await file.read()
        file_size = len(file_data)
        
        # Generate unique file key with environment prefix
        env = os.getenv("ENV", "dev")
        file_id = str(uuid.uuid4())
        file_key = f"{env}/renders/{file_id}.{format}"
        
        # Determine content type
        content_type_map = {
            "mp3": "audio/mpeg",
            "wav": "audio/wav",
        }
        content_type = content_type_map.get(format, "audio/mpeg")
        
        # Upload to S3
        s3_service = get_s3_service()
        public_url = s3_service.upload_file(file_data, file_key, content_type)
        
        if not public_url:
            raise HTTPException(status_code=500, detail="Failed to upload file to storage")
        
        # Return render object
        render = {
            "id": file_id,
            "url": public_url,
            "format": format,
            "size_bytes": file_size,
            "created_at": datetime.utcnow().isoformat() + "Z"
        }
        
        if bitrate:
            render["bitrate"] = bitrate
        if duration:
            render["duration"] = duration
        
        logger.info(f"✅ Uploaded audio file: {file_id} ({file_size} bytes)")
        return render
        
    except Exception as e:
        logger.error(f"❌ Failed to upload audio file: {e}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

