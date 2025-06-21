#!/usr/bin/env python3
"""
MongoDB Collection Initialization Script
Creates collections and indexes for application
"""

import os
from pymongo import MongoClient, ASCENDING, DESCENDING
from datetime import datetime, timezone
import logging
from typing import Dict, List, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MongoDB connection
MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
DATABASE_NAME = os.getenv("DATABASE_NAME", "niyya")

# =============================================================================
# DATA STRUCTURE CONFIGURATION
# =============================================================================

# Collection Schema Definitions
COLLECTIONS_CONFIG = {
    "profiles": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "email", "unique": True},
            {"fields": "name"},
            {"fields": "registered_at"},
            {"fields": "last_online"},
        ],
        "schema": {
            "id": "string",
            "name": "string", 
            "registered_at": "datetime",
            "last_online": "datetime",
            "email": "string",
            "info": "string"
        }
    },
    "soundseries": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "user_id"},  # Reference to user
            {"fields": [("user_id", ASCENDING), ("created", DESCENDING)]},
            {"fields": "collaborators.user_id"},
            {"fields": "plays_num"},
            {"fields": "forks_num"},
            {"fields": "created"},
            {"fields": "visibility"},
            {"fields": "tags"},
            {"fields": [("plays_num", DESCENDING)]},  # For trending
            {"fields": [("created", DESCENDING)]},   # For recent
        ],
        "schema": {
            "id": "string",
            "user_id": "string",  # Reference to profiles.id
            "name": "string",
            "created": "datetime",
            "lastmodified": "datetime",
            "plays_num": "number",
            "forks_num": "number",
            "edit_lock": "boolean",
            "parent_id": "string",
            "audio": "object",
            "collaborators": "array",
            "tags": "array",
            "visibility": "string"
        }
    }
}

# Sample Data Templates
SAMPLE_DATA_TEMPLATES = {
    "profiles": [
        {
            "id": "user123",
            "name": "John Producer",
            "registered_at": "2024-01-01T00:00:00Z",
            "last_online": "2024-01-25T15:30:00Z",
            "email": "john@example.com",
            "info": "Music producer and beat maker"
        },
        {
            "id": "user456",
            "name": "Sarah Mixer",
            "registered_at": "2024-01-05T10:15:00Z",
            "last_online": "2024-01-25T12:00:00Z",
            "email": "sarah@example.com",
            "info": "Electronic music enthusiast"
        },
        {
            "id": "user789",
            "name": "Mike Collaborator",
            "registered_at": "2024-01-10T14:20:00Z",
            "last_online": "2024-01-24T18:45:00Z",
            "email": "mike@example.com",
            "info": "Sound engineer and collaborator"
        }
    ],
    "soundseries": [
        {
            "id": "ss_001",
            "user_id": "user123",
            "name": "My First Beat",
            "created": "2024-01-15T10:30:00Z",
            "lastmodified": "2024-01-20T14:15:00Z",
            "plays_num": 42,
            "forks_num": 3,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 120.5,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/ss_001.mp3"
            },
            "collaborators": [
                {
                    "user_id": "user456",
                    "role": "editor", 
                    "joined_at": "2024-01-16T12:00:00Z"
                }
            ],
            "tags": ["electronic", "beat", "loop"],
            "visibility": "public"
        },
        {
            "id": "ss_002",
            "user_id": "user123", 
            "name": "Bass Drop Mix",
            "created": "2024-01-18T09:45:00Z",
            "lastmodified": "2024-01-24T11:20:00Z",
            "plays_num": 128,
            "forks_num": 8,
            "edit_lock": True,
            "parent_id": "ss_001",
            "audio": {
                "format": "mp3",
                "duration": 180.2,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/ss_002.mp3"
            },
            "collaborators": [
                {
                    "user_id": "user456",
                    "role": "editor",
                    "joined_at": "2024-01-16T12:00:00Z"
                },
                {
                    "user_id": "user789",
                    "role": "viewer",
                    "joined_at": "2024-01-18T16:30:00Z"
                }
            ],
            "tags": ["bass", "electronic", "remix"],
            "visibility": "public"
        },
        {
            "id": "ss_003",
            "user_id": "user123",
            "name": "Latest Beat",
            "created": "2024-01-25T10:00:00Z", 
            "lastmodified": "2024-01-25T10:00:00Z",
            "plays_num": 5,
            "forks_num": 0,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 95.3,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/ss_003.mp3"
            },
            "collaborators": [],
            "tags": ["experimental", "new"],
            "visibility": "public"
        },
        {
            "id": "ss_004",
            "user_id": "user456",
            "name": "Ambient Dreams",
            "created": "2024-01-22T16:15:00Z",
            "lastmodified": "2024-01-23T09:30:00Z",
            "plays_num": 18,
            "forks_num": 1,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 240.8,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/ss_004.mp3"
            },
            "collaborators": [],
            "tags": ["ambient", "chill", "atmospheric"],
            "visibility": "public"
        }
    ]
}

# =============================================================================
# INITIALIZATION FUNCTIONS
# =============================================================================

def init_mongodb(drop_existing: bool = False, insert_samples: bool = True):
    """
    Initialize MongoDB collections and indexes
    
    Args:
        drop_existing: Whether to drop existing collections
        insert_samples: Whether to insert sample data
    """
    try:
        client = MongoClient(MONGO_URL)
        db = client[DATABASE_NAME]
        
        logger.info(f"Connected to MongoDB: {MONGO_URL}")
        logger.info(f"Database: {DATABASE_NAME}")
        
        # Drop existing collections if requested
        if drop_existing:
            for collection_name in COLLECTIONS_CONFIG.keys():
                db[collection_name].drop()
                logger.info(f"🗑️  Dropped collection: {collection_name}")
        
        # Create collections and indexes
        create_collections_and_indexes(db)
        
        # Insert sample data if requested
        if insert_samples:
            insert_sample_data(db)
        
        # Verify setup
        verify_setup(db)
        
    except Exception as e:
        logger.error(f"❌ Error initializing MongoDB: {e}")
        raise
    finally:
        client.close()

def create_collections_and_indexes(db):
    """Create collections and their indexes based on configuration"""
    
    for collection_name, config in COLLECTIONS_CONFIG.items():
        collection = db[collection_name]
        
        logger.info(f"📁 Setting up collection: {collection_name}")
        
        # Create indexes
        for index_config in config["indexes"]:
            fields = index_config["fields"]
            unique = index_config.get("unique", False)
            
            try:
                if isinstance(fields, str):
                    # Single field index
                    collection.create_index(fields, unique=unique)
                elif isinstance(fields, list):
                    # Compound index
                    collection.create_index(fields, unique=unique)
                
                index_name = fields if isinstance(fields, str) else str(fields)
                logger.info(f"  ✅ Index created: {index_name}")
                
            except Exception as e:
                logger.warning(f"  ⚠️  Index creation failed for {fields}: {e}")
        
        # Log schema info
        schema_fields = list(config["schema"].keys())
        logger.info(f"  📋 Schema fields: {schema_fields}")

def insert_sample_data(db):
    """Insert sample data based on templates"""
    
    for collection_name, sample_data in SAMPLE_DATA_TEMPLATES.items():
        collection = db[collection_name]
        
        # Only insert if collection is empty
        if collection.count_documents({}) == 0:
            try:
                if len(sample_data) == 1:
                    collection.insert_one(sample_data[0])
                else:
                    collection.insert_many(sample_data)
                
                logger.info(f"✅ Sample data inserted into {collection_name}: {len(sample_data)} documents")
                
            except Exception as e:
                logger.warning(f"⚠️  Sample data insertion failed for {collection_name}: {e}")
        else:
            logger.info(f"⏭️  Skipping sample data for {collection_name} (not empty)")

def verify_setup(db):
    """Verify that collections were created properly"""
    collections = db.list_collection_names()
    
    logger.info("🔍 Verification Results:")
    
    for collection_name in COLLECTIONS_CONFIG.keys():
        if collection_name in collections:
            count = db[collection_name].count_documents({})
            logger.info(f"  ✅ {collection_name}: {count} documents")
            
            # List indexes
            indexes = list(db[collection_name].list_indexes())
            logger.info(f"     📋 Indexes ({len(indexes)}):")
            for idx in indexes:
                index_info = f"{idx['name']}: {list(idx['key'].keys())}"
                if idx.get('unique'):
                    index_info += " (unique)"
                logger.info(f"       - {index_info}")
        else:
            logger.error(f"  ❌ {collection_name}: Collection not found!")

# =============================================================================
# UTILITY FUNCTIONS FOR EASY MODIFICATION
# =============================================================================

def add_collection(name: str, indexes: List[Dict], schema: Dict[str, str], sample_data: List[Dict] = None):
    """
    Add a new collection configuration
    
    Args:
        name: Collection name
        indexes: List of index configurations
        schema: Schema definition
        sample_data: Optional sample data
    """
    COLLECTIONS_CONFIG[name] = {
        "indexes": indexes,
        "schema": schema
    }
    
    if sample_data:
        SAMPLE_DATA_TEMPLATES[name] = sample_data
    
    logger.info(f"📝 Added collection configuration: {name}")

def update_sample_data(collection_name: str, new_data: List[Dict]):
    """Update sample data for a collection"""
    SAMPLE_DATA_TEMPLATES[collection_name] = new_data
    logger.info(f"📝 Updated sample data for: {collection_name}")

def get_collection_config(collection_name: str = None):
    """Get collection configuration(s)"""
    if collection_name:
        return COLLECTIONS_CONFIG.get(collection_name)
    return COLLECTIONS_CONFIG

# =============================================================================
# MAIN EXECUTION
# =============================================================================

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Initialize MongoDB collections")
    parser.add_argument("--drop", action="store_true", help="Drop existing collections")
    parser.add_argument("--no-samples", action="store_true", help="Skip sample data insertion")
    parser.add_argument("--list-config", action="store_true", help="List current configuration")
    
    args = parser.parse_args()
    
    if args.list_config:
        print("📋 Current Configuration:")
        for name, config in COLLECTIONS_CONFIG.items():
            print(f"\n🗂️  Collection: {name}")
            print(f"   Schema: {list(config['schema'].keys())}")
            print(f"   Indexes: {len(config['indexes'])}")
            if name in SAMPLE_DATA_TEMPLATES:
                print(f"   Sample Data: {len(SAMPLE_DATA_TEMPLATES[name])} documents")
    else:
        init_mongodb(
            drop_existing=args.drop,
            insert_samples=not args.no_samples
        ) 