#!/usr/bin/env python3
"""
MongoDB Collection Initialization Script
Creates collections and indexes for application
"""

import os
import uuid
from pymongo import MongoClient, ASCENDING, DESCENDING
from datetime import datetime, timezone
import logging
from typing import Dict, List, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MongoDB connection with authentication
MONGO_URL = "mongodb://admin:test@mongodb:27017/admin?authSource=admin"
DATABASE_NAME = "admin"

# =============================================================================
# DATA STRUCTURE CONFIGURATION
# =============================================================================

# Collection Schema Definitions
COLLECTIONS_CONFIG = {
    "users": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "email", "unique": True},
            {"fields": "username", "unique": True},
            {"fields": "name", "unique": False},
            {"fields": "created_at", "unique": False},
            {"fields": "last_login", "unique": False}
        ],
        "schema": {
            "id": "string (UUID)",
            "username": "string",
            "name": "string",
            "email": "string",
            "password_hash": "string",
            "salt": "string",
            "profile": {
                "bio": "string", 
                "location": "string",
                "website": "string",
                "social_links": {
                    "twitter": "string",
                    "instagram": "string", 
                    "youtube": "string"
                }
            },
            "created_at": "datetime",
            "last_login": "datetime",
            "last_online": "datetime",
            "is_active": "boolean",
            "email_verified": "boolean",
            "stats": {
                "total_plays": "number",
                "total_likes": "number",
                "follower_count": "number",
                "following_count": "number"
            },

            "preferences": {
                "notifications_enabled": "boolean",
                "public_profile": "boolean",
                "theme": "string"
            }
        }
    },
    "threads": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "users.id", "unique": False},  # Index on user IDs for quick lookup
            {"fields": "created_at", "unique": False},
            {"fields": "updated_at", "unique": False},
            {"fields": "status", "unique": False}
        ],
        "schema": {
            "id": "string (UUID)",
            "title": "string",
            "users": [
                {
                    "id": "string (UUID)",
                    "name": "string", 
                    "joined_at": "datetime"
                }
            ],
            "checkpoints": [
                {
                    "id": "string (UUID)",
                    "user_id": "string (UUID)",
                    "user_name": "string",
                    "timestamp": "datetime",
                    "comment": "string",
                    "renders": [
                        {
                            "id": "string (UUID)",
                            "url": "string",
                            "created_at": "datetime",
                            "version": "string",
                            "quality": "string"  # high, medium, low
                        }
                    ],
                    "snapshot": {
                        "id": "string (UUID)",
                        "name": "string",
                        "createdAt": "datetime",
                        "version": "string",
                        "audio": {
                            "sources": [
                                {
                                    "scenes": [
                                        {
                                            "layers": [
                                                {
                                                    "id": "string (UUID)",
                                                    "index": "number",
                                                    "rows": [
                                                        {
                                                            "cells": [
                                                                {
                                                                    "sample": {
                                                                        "sample_id": "string (UUID)",
                                                                        "sample_name": "string"
                                                                    }
                                                                }
                                                            ]
                                                        }
                                                    ]
                                                }
                                            ],
                                            "metadata": {
                                                "user": "string",
                                                "bpm": "number",
                                                "key": "string",
                                                "time_signature": "string",
                                                "created_at": "datetime"
                                            }
                                        }
                                    ],
                                    "samples": [
                                        {
                                            "id": "string (UUID)",
                                            "name": "string",
                                            "url": "string",
                                            "is_public": "boolean"
                                        }
                                    ]
                                }
                            ]
                        }
                    }
                }
            ],
            "status": "string",  # active, paused, completed, archived
            "created_at": "datetime",
            "updated_at": "datetime",
            "metadata": {
                "original_project_id": "string (UUID) | null",  # Reference to original project if this is a collaboration
                "project_type": "string",  # collaboration, solo, remix, etc.
                "genre": "string",
                "tags": ["string"],
                "description": "string",
                "is_public": "boolean",
                "plays_num": "number",
                "likes_num": "number",
                "forks_num": "number"
            }
        }
    },
    "samples": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "user_id", "unique": False},
            {"fields": "name", "unique": False},
            {"fields": "tags", "unique": False}
        ],
        "schema": {
            "id": "string (UUID)",
            "user_id": "string (UUID)",
            "name": "string",
            "url": "string",
            "duration": "number",
            "file_size": "number",
            "format": "string",
            "sample_rate": "number",
            "channels": "number",
            "tags": ["string"],
            "is_public": "boolean",
            "created_at": "datetime",
            "plays_num": "number",
            "likes_num": "number"
        }
    }
}

# Sample Data Templates
SAMPLE_DATA_TEMPLATES = {
    "users": [
        {
            "id": "alice-test-user-001",
            "username": "dj_vegan",
            "name": "dj_vegan",
            "email": "alice@test.com",
            "password_hash": "$2b$12$xUi41tRzH5FZrf02KTRA7.RZ9/yHYefLa06UJs.dbCCqA.i2Dmpe6",  # hashed "test123"
            "salt": "$2b$12$xUi41tRzH5FZrf02KTRA7.",
            "profile": {
                "bio": "Electronic music producer and sound designer",
                "location": "Los Angeles, CA",
                "website": "https://alicejohnson.com",
                "social_links": {
                    "twitter": "@alicej",
                    "instagram": "@alicebeats",
                    "youtube": "AliceJohnsonMusic"
                }
            },
            "created_at": "2024-01-15T10:30:00Z",
            "last_login": "2024-12-06T15:45:00Z",
            "last_online": "2024-03-20T14:22:00Z",
            "is_active": True,
            "email_verified": True,
            "stats": {
                "total_plays": 15420,
                "total_likes": 892,
                "follower_count": 245,
                "following_count": 180
            },

            "preferences": {
                "notifications_enabled": True,
                "public_profile": True,
                "theme": "dark"
            }
        },
        {
            "id": "bob-test-user-002", 
            "username": "dj_rodry",
            "name": "dj_rodry",
            "email": "bob@test.com",
            "password_hash": "$2b$12$xUi41tRzH5FZrf02KTRA7.RZ9/yHYefLa06UJs.dbCCqA.i2Dmpe6",  # hashed "test123"
            "salt": "$2b$12$xUi41tRzH5FZrf02KTRA7.",
            "profile": {
                "bio": "Hip-hop and trap music creator",
                "location": "Atlanta, GA",
                "website": "",
                "social_links": {
                    "twitter": "@bobsmith",
                    "instagram": "@bobbeatsofficial",
                    "youtube": ""
                }
            },
            "created_at": "2024-02-01T09:15:00Z",
            "last_login": "2024-12-05T12:30:00Z",
            "last_online": "2024-03-19T16:45:00Z",
            "is_active": True,
            "email_verified": True,
            "stats": {
                "total_plays": 8930,
                "total_likes": 456,
                "follower_count": 189,
                "following_count": 203
            },

            "preferences": {
                "notifications_enabled": True,
                "public_profile": True,
                "theme": "light"
            }
        }
    ],
    "threads": [],
    "samples": [
        {
            "id": "sample_kick_001",
            "user_id": "660e8400-e29b-41d4-a716-446655440001",
            "name": "Kick Heavy",
            "url": "https://example.com/samples/kick_heavy.wav",
            "duration": 1.2,
            "file_size": 52480,
            "format": "wav",
            "sample_rate": 44100,
            "channels": 1,
            "tags": ["kick", "heavy", "electronic"],
            "is_public": True,
            "created_at": "2024-03-10T12:00:00Z",
            "plays_num": 1250,
            "likes_num": 89
        },
        {
            "id": "sample_snare_001",
            "user_id": "660e8400-e29b-41d4-a716-446655440002",
            "name": "Snare Crisp",
            "url": "https://example.com/samples/snare_crisp.wav", 
            "duration": 0.8,
            "file_size": 35840,
            "format": "wav",
            "sample_rate": 44100,
            "channels": 1,
            "tags": ["snare", "crisp", "acoustic"],
            "is_public": True,
            "created_at": "2024-03-12T15:30:00Z",
            "plays_num": 980,
            "likes_num": 67
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
    parser.add_argument("--drop", action="store_True", help="Drop existing collections")
    parser.add_argument("--no-samples", action="store_True", help="Skip sample data insertion")
    parser.add_argument("--list-config", action="store_True", help="List current configuration")
    
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