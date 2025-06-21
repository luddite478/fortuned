#!/usr/bin/env python3
"""
Database Design Patterns for User-Soundseries Relationship
Demonstrates different approaches to handle one-to-many relationships in MongoDB
"""

# =============================================================================
# APPROACH 1: EMBEDDING (Current) - Good for small datasets
# =============================================================================

# USER COLLECTION - With embedded soundseries metadata
USER_EMBEDDING_PATTERN = {
    "id": "user123",
    "name": "John Producer", 
    "email": "john@example.com",
    "registered_at": "2024-01-01T00:00:00Z",
    "last_online": "2024-01-25T15:30:00Z",
    "info": "Music producer",
    # EMBEDDED: Quick access but can grow large
    "soundseries_meta": [
        {
            "id": "ss_001",
            "name": "My First Beat",
            "plays_num": 42,
            "forks_num": 3,
            "created": "2024-01-15T10:30:00Z",
            "lastmodified": "2024-01-20T14:15:00Z"
        }
    ],
    # Stats for quick display
    "stats": {
        "total_soundseries": 15,
        "total_plays": 1250,
        "total_forks": 45
    }
}

# =============================================================================
# APPROACH 2: PURE REFERENCING - Best for scalability
# =============================================================================

# USER COLLECTION - Clean and lightweight
USER_REFERENCE_PATTERN = {
    "id": "user123",
    "name": "John Producer",
    "email": "john@example.com", 
    "registered_at": "2024-01-01T00:00:00Z",
    "last_online": "2024-01-25T15:30:00Z",
    "info": "Music producer",
    # Just stats, no embedded data
    "stats": {
        "total_soundseries": 15,
        "total_plays": 1250, 
        "total_forks": 45,
        "last_soundseries_created": "2024-01-20T14:15:00Z"
    }
}

# SOUNDSERIES COLLECTION - Complete data
SOUNDSERIES_REFERENCE_PATTERN = {
    "id": "ss_001",
    "user_id": "user123",  # Reference to user
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
        "url": "https://example.com/audio/ss_001.mp3"
    },
    "collaborators": [
        {"user_id": "user456", "role": "editor"}
    ],
    "tags": ["electronic", "beat", "loop"],
    "visibility": "public"  # public, private, unlisted
}

# =============================================================================
# APPROACH 3: HYBRID (RECOMMENDED) - Best of both worlds
# =============================================================================

# USER COLLECTION - Essential info for user profile
USER_HYBRID_PATTERN = {
    "id": "user123", 
    "name": "John Producer",
    "email": "john@example.com",
    "registered_at": "2024-01-01T00:00:00Z",
    "last_online": "2024-01-25T15:30:00Z",
    "info": "Music producer",
    
    # MINIMAL metadata for quick user profile display
    "recent_soundseries": [
        {
            "id": "ss_003",
            "name": "Latest Beat", 
            "created": "2024-01-25T10:00:00Z",
            "plays_num": 5
        },
        {
            "id": "ss_002",
            "name": "Bass Drop Mix",
            "created": "2024-01-20T14:15:00Z", 
            "plays_num": 128
        }
    ],  # Only last 5-10 for user profile
    
    # Aggregated stats
    "stats": {
        "total_soundseries": 15,
        "total_plays": 1250,
        "total_forks": 45,
        "total_collaborations": 8,
        "last_activity": "2024-01-25T15:30:00Z"
    }
}

# SOUNDSERIES COLLECTION - Complete data (same as reference pattern)
SOUNDSERIES_HYBRID_PATTERN = SOUNDSERIES_REFERENCE_PATTERN.copy()

# =============================================================================
# QUERY PATTERNS FOR EACH APPROACH
# =============================================================================

QUERY_EXAMPLES = {
    "embedding": {
        "get_user_with_soundseries": """
        # Single query - fast!
        db.users.findOne({"id": "user123"})
        """,
        
        "get_all_soundseries_by_plays": """
        # Complex aggregation needed
        db.users.aggregate([
            {"$unwind": "$soundseries_meta"},
            {"$sort": {"soundseries_meta.plays_num": -1}}
        ])
        """
    },
    
    "referencing": {
        "get_user_with_soundseries": """
        # Two queries needed
        user = db.users.findOne({"id": "user123"})
        soundseries = db.soundseries.find({"user_id": "user123"})
        """,
        
        "get_all_soundseries_by_plays": """
        # Simple and fast!
        db.soundseries.find().sort({"plays_num": -1})
        """
    },
    
    "hybrid": {
        "get_user_profile": """
        # Single query for user profile (shows recent soundseries)
        db.users.findOne({"id": "user123"})
        """,
        
        "get_user_all_soundseries": """
        # Single query when need all user's soundseries
        db.soundseries.find({"user_id": "user123"}).sort({"created": -1})
        """,
        
        "get_trending_soundseries": """
        # Simple query across all soundseries
        db.soundseries.find().sort({"plays_num": -1}).limit(20)
        """
    }
}

# =============================================================================
# RECOMMENDATIONS
# =============================================================================

RECOMMENDATIONS = """
🎯 RECOMMENDED APPROACH: HYBRID

Why Hybrid is Best for Your Use Case:

✅ USER COLLECTION should contain:
   - User profile data
   - Recent/featured soundseries (5-10 items) for quick profile display
   - Aggregated stats (total plays, total soundseries, etc.)
   - No full soundseries data

✅ SOUNDSERIES COLLECTION should contain:
   - Complete soundseries data
   - user_id reference to owner
   - All metadata, audio info, collaborators
   - This is your "posts" collection

🔥 BENEFITS:
   - Fast user profile loading (single query)
   - Scalable (no document size limits)
   - Easy soundseries queries (trending, search, etc.)
   - Single source of truth for soundseries data
   - Flexible - can add features without user doc bloat

⚠️  MAINTENANCE:
   - Update user.recent_soundseries when soundseries created/updated
   - Update user.stats periodically (can be async)
   - Consider using MongoDB Change Streams for real-time updates

📊 WHEN TO USE EACH:
   - Embedding: < 100 soundseries per user, simple app
   - Referencing: Need perfect consistency, complex queries
   - Hybrid: Social media like features, 100+ soundseries per user (RECOMMENDED)
"""

if __name__ == "__main__":
    print(RECOMMENDATIONS) 