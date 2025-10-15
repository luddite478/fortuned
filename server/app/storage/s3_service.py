"""S3 Storage Service for Digital Ocean Spaces"""
import os
import boto3
from botocore.exceptions import ClientError
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class S3Service:
    def __init__(self):
        # Load configuration - exactly as in test script
        self.endpoint_url = os.getenv("S3_ENDPOINT_URL")
        self.region = os.getenv("S3_REGION")
        self.access_key = os.getenv("S3_ACCESS_KEY")
        self.secret_key = os.getenv("S3_SECRET_KEY")
        self.bucket_name = os.getenv("S3_BUCKET_NAME")
        
        # Validate configuration
        if not all([self.endpoint_url, self.access_key, self.secret_key, self.bucket_name]):
            raise ValueError("Missing S3 configuration. Please set S3_ENDPOINT_URL, S3_ACCESS_KEY, S3_SECRET_KEY, and S3_BUCKET_NAME")
        
        # Initialize boto3 client - exactly as in test script
        self.client = boto3.client(
            's3',
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name=self.region
        )
        
        logger.info(f"✅ S3 Service initialized with bucket: {self.bucket_name}")
        logger.info(f"   Endpoint: {self.endpoint_url}")
        logger.info(f"   Region: {self.region}")
    
    def upload_file(self, file_data: bytes, file_key: str, content_type: str = "audio/mpeg") -> Optional[str]:
        """Upload a file to S3 and return the public URL - matches test script exactly"""
        try:
            # Upload using put_object - exactly as in test script
            logger.info(f"📤 Uploading file: {file_key}")
            self.client.put_object(
                Bucket=self.bucket_name,
                Key=file_key,
                Body=file_data,
                ContentType=content_type,
                ACL='public-read'
            )
            
            # Construct public URL - exactly as in test script
            public_url = f"https://{self.bucket_name}.{self.endpoint_url.replace('https://', '')}/{file_key}"
            logger.info(f"✅ Upload successful! Public URL: {public_url}")
            return public_url
            
        except ClientError as e:
            logger.error(f"❌ S3 Error: {e}")
            logger.error(f"   Error Code: {e.response.get('Error', {}).get('Code', 'Unknown')}")
            logger.error(f"   Error Message: {e.response.get('Error', {}).get('Message', 'Unknown')}")
            return None
        except Exception as e:
            logger.error(f"❌ Unexpected error during upload: {e}")
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
        # Construct public URL: https://BUCKET.REGION.digitaloceanspaces.com/FILE_KEY
        return f"https://{self.bucket_name}.{self.endpoint_url.replace('https://', '')}/{file_key}"
    
    def cleanup_folder(self, prefix: str) -> bool:
        """
        Delete all files in a folder (prefix) from S3
        
        Args:
            prefix: The folder prefix to cleanup (e.g., 'stage/', 'test/')
        
        Returns:
            bool: True if cleanup was successful, False otherwise
        """
        try:
            logger.info(f"🧹 Starting S3 cleanup for folder: {prefix}")
            
            # List all objects with the given prefix
            paginator = self.client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=self.bucket_name, Prefix=prefix)
            
            deleted_count = 0
            for page in pages:
                if 'Contents' not in page:
                    logger.info(f"✅ No files found in {prefix}")
                    return True
                
                # Prepare batch delete (max 1000 objects per request)
                objects_to_delete = [{'Key': obj['Key']} for obj in page['Contents']]
                
                if objects_to_delete:
                    response = self.client.delete_objects(
                        Bucket=self.bucket_name,
                        Delete={'Objects': objects_to_delete}
                    )
                    
                    deleted_count += len(objects_to_delete)
                    
                    if 'Errors' in response:
                        for error in response['Errors']:
                            logger.error(f"❌ Failed to delete {error['Key']}: {error['Message']}")
            
            logger.info(f"✅ S3 cleanup complete! Deleted {deleted_count} files from {prefix}")
            return True
            
        except ClientError as e:
            logger.error(f"❌ S3 cleanup failed: {e}")
            logger.error(f"   Error Code: {e.response.get('Error', {}).get('Code', 'Unknown')}")
            logger.error(f"   Error Message: {e.response.get('Error', {}).get('Message', 'Unknown')}")
            return False
        except Exception as e:
            logger.error(f"❌ Unexpected error during S3 cleanup: {e}")
            return False

# Global instance
_s3_service: Optional[S3Service] = None

def get_s3_service() -> S3Service:
    """Get or create S3 service instance"""
    global _s3_service
    if _s3_service is None:
        _s3_service = S3Service()
    return _s3_service

