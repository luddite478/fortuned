"""S3 Storage Service for Digital Ocean Spaces"""
import os
import boto3
from botocore.exceptions import ClientError
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class S3Service:
    def __init__(self):
        self.endpoint_url = os.getenv("S3_ENDPOINT_URL")
        self.region = os.getenv("S3_REGION")
        self.access_key = os.getenv("S3_ACCESS_KEY")
        self.secret_key = os.getenv("S3_SECRET_KEY")
        self.bucket_name = os.getenv("S3_BUCKET_NAME")
        
        if not all([self.endpoint_url, self.access_key, self.secret_key, self.bucket_name]):
            raise ValueError("Missing S3 configuration.")
        
        self.client = boto3.client(
            's3',
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name=self.region
        )
        
        logger.info(f"✅ S3 Service initialized with bucket: {self.bucket_name}")
    
    def upload_file(self, file_data: bytes, file_key: str, content_type: str = "audio/mpeg") -> Optional[str]:
        """Upload a file to S3 and return the public URL"""
        try:
            self.client.put_object(
                Bucket=self.bucket_name,
                Key=file_key,
                Body=file_data,
                ContentType=content_type,
                ACL='public-read'
            )
            
            public_url = f"{self.endpoint_url}/{file_key}"
            logger.info(f"✅ Uploaded file to S3: {public_url}")
            return public_url
            
        except ClientError as e:
            logger.error(f"❌ Failed to upload file to S3: {e}")
            return None
    
    def delete_file(self, file_key: str) -> bool:
        """Delete a file from S3"""
        try:
            self.client.delete_object(
                Bucket=self.bucket_name,
                Key=file_key
            )
            logger.info(f"✅ Deleted file from S3: {file_key}")
            return True
            
        except ClientError as e:
            logger.error(f"❌ Failed to delete file from S3: {e}")
            return False
    
    def get_file_url(self, file_key: str) -> str:
        """Get public URL for a file"""
        return f"{self.endpoint_url}/{file_key}"

# Global instance
_s3_service: Optional[S3Service] = None

def get_s3_service() -> S3Service:
    """Get or create S3 service instance"""
    global _s3_service
    if _s3_service is None:
        _s3_service = S3Service()
    return _s3_service

