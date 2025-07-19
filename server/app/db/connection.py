import os
import logging
from pymongo import MongoClient
from typing import Optional

# Configure logging
logger = logging.getLogger(__name__)

# MongoDB configuration from environment variables
MONGO_URL = os.getenv("MONGO_URL", "mongodb://admin:test@mongodb:27017/admin?authSource=admin")
DATABASE_NAME = os.getenv("MONGO_DATABASE", "admin")

# Global MongoDB client instance
_client: Optional[MongoClient] = None
_database = None

def get_mongodb_client() -> MongoClient:
    """Get MongoDB client instance (singleton pattern)"""
    global _client
    if _client is None:
        logger.info(f"Connecting to MongoDB: {MONGO_URL}")
        _client = MongoClient(MONGO_URL)
        
        # Test the connection
        try:
            _client.admin.command('ping')
            logger.info("✅ MongoDB connection successful")
        except Exception as e:
            logger.error(f"❌ MongoDB connection failed: {e}")
            raise
    
    return _client

def get_database():
    """Get MongoDB database instance"""
    global _database
    if _database is None:
        client = get_mongodb_client()
        _database = client[DATABASE_NAME]
        logger.info(f"📁 Using database: {DATABASE_NAME}")
    
    return _database

def close_connection():
    """Close MongoDB connection"""
    global _client, _database
    if _client:
        _client.close()
        _client = None
        _database = None
        logger.info("🔌 MongoDB connection closed") 