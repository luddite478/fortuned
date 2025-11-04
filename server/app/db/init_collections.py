#!/usr/bin/env python3
"""
MongoDB Collection Initialization Script
Creates collections and indexes for application
"""

import os
import uuid
import json
from pymongo import MongoClient, ASCENDING, DESCENDING
from datetime import datetime, timezone
import logging
from typing import Dict, List, Any
from .connection import get_database
from jsonschema import validate, ValidationError

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# DATA STRUCTURE CONFIGURATION
# =============================================================================

# Load JSON Schemas
def load_json_schema(collection_name: str) -> Dict:
    """Load JSON schema for a collection from the repository schemas/0.0.1 directory"""
    # Determine repository root relative to this file: .../server/app/db -> go up 3 levels
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
    schemas_root = os.path.join(repo_root, 'schemas', '0.0.1')

    collection_to_schema_path = {
        'users': os.path.join(schemas_root, 'user', 'user.json'),
        'threads': os.path.join(schemas_root, 'thread', 'thread.json'),
        'samples': os.path.join(schemas_root, 'sample', 'sample.json'),
        'messages': os.path.join(schemas_root, 'thread', 'message.json'),
    }

    schema_path = collection_to_schema_path.get(collection_name)
    if not schema_path:
        logger.warning(f"No schema mapping found for collection: {collection_name}")
        return {}

    try:
        with open(schema_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        logger.warning(f"Schema file not found: {schema_path}")
        return {}
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in schema file {schema_path}: {e}")
        return {}

# Load all schemas
JSON_SCHEMAS = {
    "users": load_json_schema("users"),
    "threads": load_json_schema("threads"),
    "samples": load_json_schema("samples"),
    "messages": load_json_schema("messages"),
}

# Collection Schema Definitions
COLLECTIONS_CONFIG = {
    "users": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "email", "unique": True},
            {"fields": "username", "unique": False},  # Allow duplicate usernames (including empty)
            {"fields": "created_at", "unique": False},
            {"fields": "last_login", "unique": False}
        ],
        "schema": {k: v for k, v in JSON_SCHEMAS.get("users", {}).get("properties", {}).items()}
    },
    "threads": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "users.id", "unique": False},
            {"fields": "created_at", "unique": False},
            {"fields": "updated_at", "unique": False}
        ],
        "schema": {k: v for k, v in JSON_SCHEMAS.get("threads", {}).get("properties", {}).items()}
    },
    "samples": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "user_id", "unique": False},
            {"fields": "sample_pack_id", "unique": False},
            {"fields": "created_at", "unique": False}
        ],
        "schema": {k: v for k, v in JSON_SCHEMAS.get("samples", {}).get("properties", {}).items()}
    },
    "messages": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "parent_thread", "unique": False},
            {"fields": [("parent_thread", ASCENDING), ("timestamp", ASCENDING)], "unique": False},
            {"fields": "user_id", "unique": False},
            {"fields": "created_at", "unique": False}
        ],
        "schema": {k: v for k, v in JSON_SCHEMAS.get("messages", {}).get("properties", {}).items()}
    }
}

# Sample Data Templates
SAMPLE_DATA_TEMPLATES = {
    "users": [
        {
            "schema_version": 1,
            "id": "64c0a6f4e5b1a2c3d4e5f601",
            "username": "dj_vegan",
            "name": "dj_vegan",
            "email": "dj_vegan@test.com",
            "created_at": "2024-01-15T10:30:00Z",
            "last_login": "2024-12-06T15:45:00Z",
            "last_online": "2024-03-20T14:22:00Z",
            "email_verified": True,
            "preferences": {"theme": "dark"},
            "threads": [],
            "following": [],
            "pending_invites_to_threads": []
        },
        {
            "schema_version": 1,
            "id": "64c0a6f4e5b1a2c3d4e5f602",
            "username": "dj_rodry",
            "name": "dj_rodry",
            "email": "dj_rodry@test.com",
            "created_at": "2024-02-01T09:15:00Z",
            "last_login": "2024-12-05T12:30:00Z",
            "last_online": "2024-03-19T16:45:00Z",
            "email_verified": True,
            "preferences": {"theme": "light"},
            "threads": [],
            "following": [],
            "pending_invites_to_threads": []
        }
    ],
    "samples": [
        {
            "schema_version": 1,
            "id": "aaaaaaaaaaaaaaaaaaaaaaaa",
            "user_id": "bbbbbbbbbbbbbbbbbbbbbbbb",
            "name": "Kick Heavy",
            "url": "https://example.com/samples/kick_heavy.wav",
            "duration": 1.2,
            "file_size": 52480,
            "format": "wav",
            "sample_rate": 44100,
            "created_at": "2024-03-10T12:00:00Z",
            "status": {
                "loaded": False,
                "file_path": "",
                "sample_id": "aaaaaaaaaaaaaaaaaaaaaaaa",
                "name": "Kick Heavy",
                "settings": {"volume": 1.0, "pitch": 1.0}
            }
        }
    ]
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

def validate_document(collection_name: str, document: Dict) -> bool:
    """
    Validate a document against its JSON schema
    
    Args:
        collection_name: Name of the collection
        document: Document to validate
        
    Returns:
        bool: True if valid, False otherwise
    """
    schema = JSON_SCHEMAS.get(collection_name)
    if not schema:
        logger.warning(f"No schema found for collection: {collection_name}")
        return True  # Skip validation if no schema
    
    try:
        validate(instance=document, schema=schema)
        return True
    except ValidationError as e:
        logger.error(f"Validation error for {collection_name}: {e.message}")
        return False
    except Exception as e:
        logger.error(f"Unexpected validation error for {collection_name}: {e}")
        return False

def validate_sample_data():
    """Validate all sample data against their schemas"""
    logger.info("🔍 Validating sample data against JSON schemas...")
    
    for collection_name, sample_data in SAMPLE_DATA_TEMPLATES.items():
        if not sample_data:
            continue
            
        schema = JSON_SCHEMAS.get(collection_name)
        if not schema:
            logger.warning(f"No schema found for {collection_name}, skipping validation")
            continue
            
        for i, document in enumerate(sample_data):
            if not validate_document(collection_name, document):
                logger.error(f"Sample data validation failed for {collection_name}[{i}]")
                return False
                
        logger.info(f"✅ Sample data validation passed for {collection_name}")
    
    return True

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
        db = get_database()
        
        logger.info("🗄️  Initializing MongoDB collections...")
        
        # Drop existing collections if requested
        if drop_existing:
            for collection_name in COLLECTIONS_CONFIG.keys():
                db[collection_name].drop()
                logger.info(f"🗑️  Dropped collection: {collection_name}")
        
        # Create collections and indexes
        create_collections_and_indexes(db)
        
        # Validate sample data before insertion
        if insert_samples:
            if not validate_sample_data():
                logger.error("❌ Sample data validation failed. Aborting initialization.")
                return False
            insert_sample_data(db)
        
        # Verify setup
        verify_setup(db)
        
    except Exception as e:
        logger.error(f"❌ Error initializing MongoDB: {e}")
        raise

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