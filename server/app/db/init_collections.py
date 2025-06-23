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
    "profiles": {
        "indexes": [
            {"fields": "id", "unique": True},
            {"fields": "email", "unique": True},
            {"fields": "name"},
            {"fields": "registered_at"},
            {"fields": "last_online"},
        ],
        "schema": {
            "id": "string (UUID)",  # UUID format: 550e8400-e29b-41d4-a716-446655440001
            "name": "string",  # User display name
            "registered_at": "datetime",  # When user registered
            "last_online": "datetime",  # Last activity timestamp
            "email": "string",  # User email (unique)
            "info": "string"  # User bio/description
        }
    },
    "projects": {
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
            {"fields": "audio.sources.scenes.metadata.user"},  # For grid creators
            {"fields": "audio.sources.samples.id"},  # For sample lookups
            {"fields": "audio.renders.quality"},  # For render quality filtering
        ],
        "schema": {
            "id": "string (UUID)",  # UUID format: 660e8400-e29b-41d4-a716-446655440001
            "user_id": "string (UUID)",  # Reference to profiles.id (UUID format)
            "name": "string",
            "created": "datetime",
            "lastmodified": "datetime", 
            "plays_num": "number",
            "forks_num": "number",
            "edit_lock": "boolean",
            "parent_id": "string (UUID) | null",  # Reference to another project
            "audio": {
                "format": "string",  # mp3, wav, etc.
                "duration": "number",  # seconds
                "sample_rate": "number",  # 44100, 48000, etc.
                "channels": "number",  # 1 (mono), 2 (stereo)
                "url": "string",  # Main audio file URL
                "renders": [
                    {
                        "id": "string",  # render_001, render_002, etc.
                        "url": "string",  # Rendered audio file URL
                        "created_at": "datetime",
                        "version": "string",  # 1.0, 2.1, etc.
                        "quality": "string"  # low, medium, high, ultra
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                     {
                                         "id": "string",  # layer_001, layer_002, etc.
                                         "index": "number",  # 0, 1, 2, 3, etc. (layer position)
                                         "rows": [
                                             {
                                                 "cells": [
                                                     {
                                                         "sample": {
                                                             "sample_id": "string | null",
                                                             "sample_name": "string | null"
                                                         }
                                                     }
                                                 ]
                                             }
                                         ]
                                     }
                                 ],
                                "metadata": {
                                    "user": "string (UUID)",  # Who created this grid
                                    "created_at": "datetime",
                                    "bpm": "number",
                                    "key": "string",  # C Major, D Minor, etc.
                                    "time_signature": "string"  # 4/4, 3/4, etc.
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "string",  # kick_01, snare_02, etc.
                                "name": "string",  # Human readable name
                                "url": "string",  # Sample audio file URL
                                "is_public": "boolean"  # Can others use this sample
                            }
                        ]
                    }
                ]
            },
            "collaborators": [
                {
                    "user_id": "string (UUID)",
                    "role": "string",  # editor, viewer, etc.
                    "joined_at": "datetime"
                }
            ],
            "tags": ["string"],  # Array of tag strings
            "visibility": "string"  # public, private, unlisted
        }
    }
}

# Sample Data Templates
SAMPLE_DATA_TEMPLATES = {
    "profiles": [
        {
            "id": "550e8400-e29b-41d4-a716-446655440001",
            "name": "John Producer",
            "registered_at": "2024-01-01T00:00:00Z",
            "last_online": "2024-01-25T15:30:00Z",
            "email": "john@example.com",
            "info": "Music producer and beat maker"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440002",
            "name": "Sarah Mixer",
            "registered_at": "2024-01-05T10:15:00Z",
            "last_online": "2024-01-25T12:00:00Z",
            "email": "sarah@example.com",
            "info": "Electronic music enthusiast"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440003",
            "name": "Mike Collaborator",
            "registered_at": "2024-01-10T14:20:00Z",
            "last_online": "2024-01-24T18:45:00Z",
            "email": "mike@example.com",
            "info": "Sound engineer and collaborator"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440004",
            "name": "Alex Beat",
            "registered_at": "2024-01-12T08:00:00Z",
            "last_online": "2024-01-25T09:15:00Z",
            "email": "alex@example.com",
            "info": "Lo-fi producer and beat maker"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440005",
            "name": "Maya Synth",
            "registered_at": "2024-01-15T14:30:00Z",
            "last_online": "2024-01-25T16:45:00Z",
            "email": "maya@example.com",
            "info": "Synthesizer enthusiast and electronic music composer"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440006",
            "name": "Jordan Mix",
            "registered_at": "2024-01-18T11:20:00Z",
            "last_online": "2024-01-24T20:30:00Z",
            "email": "jordan@example.com",
            "info": "Audio engineer and mixing specialist"
        }
    ],
            "projects": [
        {
            "id": "660e8400-e29b-41d4-a716-446655440001",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
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
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440001.mp3",
                "renders": [
                    {
                        "id": "render_001",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440001_render_001.mp3",
                        "created_at": "2024-01-20T14:15:00Z",
                        "version": "1.0",
                        "quality": "high"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    {
                                        "id": "layer_001",
                                        "index": 0,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": "kick_01", "sample_name": "Kick Basic"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "kick_01", "sample_name": "Kick Basic"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}}
                                                ]
                                            }
                                        ]
                                    },
                                    {
                                        "id": "layer_002",
                                        "index": 1,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_01", "sample_name": "Snare Tight"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_01", "sample_name": "Snare Tight"}}
                                                ]
                                            }
                                        ]
                                    },
                                    {
                                        "id": "layer_003",
                                        "index": 2,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"}},
                                                    {"sample": {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"}},
                                                    {"sample": {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"}},
                                                    {"sample": {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"}}
                                                ]
                                            }
                                        ]
                                    },
                                    {
                                        "id": "layer_004",
                                        "index": 3,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "bass_01", "sample_name": "Bass Deep"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}}
                                                ]
                                            }
                                        ]
                                    }
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440001",
                                    "created_at": "2024-01-15T10:30:00Z",
                                    "bpm": 120,
                                    "key": "C Major",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "kick_01",
                                "name": "Kick Basic",
                                "url": "https://example.com/samples/kick_01.wav",
                                "is_public": True
                            },
                            {
                                "id": "snare_01",
                                "name": "Snare Tight",
                                "url": "https://example.com/samples/snare_01.wav",
                                "is_public": True
                            },
                            {
                                "id": "hihat_01",
                                "name": "Hi-Hat Closed",
                                "url": "https://example.com/samples/hihat_01.wav",
                                "is_public": True
                            },
                            {
                                "id": "bass_01",
                                "name": "Bass Deep",
                                "url": "https://example.com/samples/bass_01.wav",
                                "is_public": False
                            }
                        ]
                    }
                ]
            },
            "collaborators": [
                {
                    "user_id": "550e8400-e29b-41d4-a716-446655440002",
                    "role": "editor", 
                    "joined_at": "2024-01-16T12:00:00Z"
                }
            ],
            "tags": ["electronic", "beat", "loop"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440002",
            "user_id": "550e8400-e29b-41d4-a716-446655440001", 
            "name": "Bass Drop Mix",
            "created": "2024-01-18T09:45:00Z",
            "lastmodified": "2024-01-24T11:20:00Z",
            "plays_num": 128,
            "forks_num": 8,
            "edit_lock": True,
            "parent_id": "660e8400-e29b-41d4-a716-446655440001",
            "audio": {
                "format": "mp3",
                "duration": 180.2,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440002.mp3",
                "renders": [
                    {
                        "id": "render_002",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440002_render_002.mp3",
                        "created_at": "2024-01-24T11:20:00Z",
                        "version": "2.1",
                        "quality": "high"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    {
                                        "id": "layer_005",
                                        "index": 0,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": "kick_02", "sample_name": "Kick Heavy"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "kick_02", "sample_name": "Kick Heavy"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "kick_02", "sample_name": "Kick Heavy"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "kick_02", "sample_name": "Kick Heavy"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}}
                                                ]
                                            }
                                        ]
                                    },
                                    {
                                        "id": "layer_006",
                                        "index": 1,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_02", "sample_name": "Snare Clap"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_02", "sample_name": "Snare Clap"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_02", "sample_name": "Snare Clap"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "snare_02", "sample_name": "Snare Clap"}}
                                                ]
                                            }
                                        ]
                                    },
                                    {
                                        "id": "layer_007",
                                        "index": 2,
                                        "rows": [
                                            {
                                                "cells": [
                                                    {"sample": {"sample_id": "bass_02", "sample_name": "Bass Drop"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "bass_02", "sample_name": "Bass Drop"}},
                                                    {"sample": {"sample_id": "bass_02", "sample_name": "Bass Drop"}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": None, "sample_name": None}},
                                                    {"sample": {"sample_id": "bass_02", "sample_name": "Bass Drop"}}
                                                ]
                                            }
                                        ]
                                    }
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440001",
                                    "created_at": "2024-01-18T09:45:00Z",
                                    "bpm": 140,
                                    "key": "D Minor",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "kick_02",
                                "name": "Kick Heavy",
                                "url": "https://example.com/samples/kick_02.wav",
                                "is_public": True
                            },
                            {
                                "id": "snare_02",
                                "name": "Snare Clap",
                                "url": "https://example.com/samples/snare_02.wav",
                                "is_public": True
                            },
                            {
                                "id": "bass_02",
                                "name": "Bass Drop",
                                "url": "https://example.com/samples/bass_02.wav",
                                "is_public": False
                            }
                        ]
                    }
                ]
            },
            "collaborators": [
                {
                    "user_id": "550e8400-e29b-41d4-a716-446655440002",
                    "role": "editor",
                    "joined_at": "2024-01-16T12:00:00Z"
                },
                {
                    "user_id": "550e8400-e29b-41d4-a716-446655440003",
                    "role": "viewer",
                    "joined_at": "2024-01-18T16:30:00Z"
                }
            ],
            "tags": ["bass", "electronic", "remix"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440003",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
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
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440003.mp3",
                "renders": [
                    {
                        "id": "render_003",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440003_render_003.mp3",
                        "created_at": "2024-01-25T10:00:00Z",
                        "version": "1.0",
                        "quality": "medium"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    [
                                        {"id": "layer_041", "index": 0, "sample": {"sample_id": "kick_03", "sample_name": "Kick Experimental"}},
                                        {"id": "layer_042", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_043", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_044", "index": 3, "sample": {"sample_id": "kick_03", "sample_name": "Kick Experimental"}}
                                    ],
                                    [
                                        {"id": "layer_045", "index": 0, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_046", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_047", "index": 2, "sample": {"sample_id": "perc_01", "sample_name": "Perc Weird"}},
                                        {"id": "layer_048", "index": 3, "sample": {"sample_id": None, "sample_name": None}}
                                    ]
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440001",
                                    "created_at": "2024-01-25T10:00:00Z",
                                    "bpm": 95,
                                    "key": "F# Minor",
                                    "time_signature": "3/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "kick_03",
                                "name": "Kick Experimental",
                                "url": "https://example.com/samples/kick_03.wav",
                                "is_public": False
                            },
                            {
                                "id": "perc_01",
                                "name": "Perc Weird",
                                "url": "https://example.com/samples/perc_01.wav",
                                "is_public": True
                            }
                        ]
                    }
                ]
            },
            "collaborators": [],
            "tags": ["experimental", "new"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440004",
            "user_id": "550e8400-e29b-41d4-a716-446655440002",
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
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440004.mp3",
                "renders": [
                    {
                        "id": "render_004",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440004_render_004.mp3",
                        "created_at": "2024-01-23T09:30:00Z",
                        "version": "1.3",
                        "quality": "high"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    [
                                        {"id": "layer_049", "index": 0, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}},
                                        {"id": "layer_050", "index": 1, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}},
                                        {"id": "layer_051", "index": 2, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}},
                                        {"id": "layer_052", "index": 3, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}},
                                        {"id": "layer_053", "index": 4, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}},
                                        {"id": "layer_054", "index": 5, "sample": {"sample_id": "pad_01", "sample_name": "Pad Ambient"}}
                                    ],
                                    [
                                        {"id": "layer_055", "index": 0, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_056", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_057", "index": 2, "sample": {"sample_id": "texture_01", "sample_name": "Texture Soft"}},
                                        {"id": "layer_058", "index": 3, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_059", "index": 4, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_060", "index": 5, "sample": {"sample_id": "texture_01", "sample_name": "Texture Soft"}}
                                    ]
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440002",
                                    "created_at": "2024-01-22T16:15:00Z",
                                    "bpm": 85,
                                    "key": "A Major",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "pad_01",
                                "name": "Pad Ambient",
                                "url": "https://example.com/samples/pad_01.wav",
                                "is_public": True
                            },
                            {
                                "id": "texture_01",
                                "name": "Texture Soft",
                                "url": "https://example.com/samples/texture_01.wav",
                                "is_public": True
                            }
                        ]
                    }
                ]
            },
            "collaborators": [],
            "tags": ["ambient", "chill", "atmospheric"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440005",
            "user_id": "550e8400-e29b-41d4-a716-446655440004",
            "name": "Lo-fi Chill Collection",
            "created": "2024-01-20T14:00:00Z",
            "lastmodified": "2024-01-24T16:30:00Z",
            "plays_num": 67,
            "forks_num": 5,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 195.7,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440005.mp3",
                "renders": [
                    {
                        "id": "render_005",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440005_render_005.mp3",
                        "created_at": "2024-01-24T16:30:00Z",
                        "version": "2.0",
                        "quality": "high"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    [
                                        {"id": "layer_061", "index": 0, "sample": {"sample_id": "kick_lofi", "sample_name": "Kick Lo-fi"}},
                                        {"id": "layer_062", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_063", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_064", "index": 3, "sample": {"sample_id": "kick_lofi", "sample_name": "Kick Lo-fi"}}
                                    ],
                                    [
                                        {"id": "layer_065", "index": 0, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_066", "index": 1, "sample": {"sample_id": "snare_lofi", "sample_name": "Snare Dusty"}},
                                        {"id": "layer_067", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_068", "index": 3, "sample": {"sample_id": "snare_lofi", "sample_name": "Snare Dusty"}}
                                    ],
                                    [
                                        {"id": "layer_069", "index": 0, "sample": {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"}},
                                        {"id": "layer_070", "index": 1, "sample": {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"}},
                                        {"id": "layer_071", "index": 2, "sample": {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"}},
                                        {"id": "layer_072", "index": 3, "sample": {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"}}
                                    ]
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440004",
                                    "created_at": "2024-01-20T14:00:00Z",
                                    "bpm": 75,
                                    "key": "G Major",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "kick_lofi",
                                "name": "Kick Lo-fi",
                                "url": "https://example.com/samples/kick_lofi.wav",
                                "is_public": True
                            },
                            {
                                "id": "snare_lofi",
                                "name": "Snare Dusty",
                                "url": "https://example.com/samples/snare_lofi.wav",
                                "is_public": True
                            },
                            {
                                "id": "vinyl_01",
                                "name": "Vinyl Crackle",
                                "url": "https://example.com/samples/vinyl_01.wav",
                                "is_public": False
                            }
                        ]
                    }
                ]
            },
            "collaborators": [],
            "tags": ["lo-fi", "chill", "study"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440006",
            "user_id": "550e8400-e29b-41d4-a716-446655440005",
            "name": "Synth Waves",
            "created": "2024-01-23T11:45:00Z",
            "lastmodified": "2024-01-25T08:20:00Z",
            "plays_num": 34,
            "forks_num": 2,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 156.3,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440006.mp3",
                "renders": [
                    {
                        "id": "render_006",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440006_render_006.mp3",
                        "created_at": "2024-01-25T08:20:00Z",
                        "version": "1.1",
                        "quality": "high"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    [
                                        {"id": "layer_073", "index": 0, "sample": {"sample_id": "synth_lead", "sample_name": "Synth Lead"}},
                                        {"id": "layer_074", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_075", "index": 2, "sample": {"sample_id": "synth_lead", "sample_name": "Synth Lead"}},
                                        {"id": "layer_076", "index": 3, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_077", "index": 4, "sample": {"sample_id": "synth_lead", "sample_name": "Synth Lead"}},
                                        {"id": "layer_078", "index": 5, "sample": {"sample_id": None, "sample_name": None}}
                                    ],
                                    [
                                        {"id": "layer_079", "index": 0, "sample": {"sample_id": "synth_bass", "sample_name": "Synth Bass"}},
                                        {"id": "layer_080", "index": 1, "sample": {"sample_id": "synth_bass", "sample_name": "Synth Bass"}},
                                        {"id": "layer_081", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_082", "index": 3, "sample": {"sample_id": "synth_bass", "sample_name": "Synth Bass"}},
                                        {"id": "layer_083", "index": 4, "sample": {"sample_id": "synth_bass", "sample_name": "Synth Bass"}},
                                        {"id": "layer_084", "index": 5, "sample": {"sample_id": None, "sample_name": None}}
                                    ],
                                    [
                                        {"id": "layer_085", "index": 0, "sample": {"sample_id": "drum_retro", "sample_name": "Drum Retro"}},
                                        {"id": "layer_086", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_087", "index": 2, "sample": {"sample_id": "drum_retro", "sample_name": "Drum Retro"}},
                                        {"id": "layer_088", "index": 3, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_089", "index": 4, "sample": {"sample_id": "drum_retro", "sample_name": "Drum Retro"}},
                                        {"id": "layer_090", "index": 5, "sample": {"sample_id": None, "sample_name": None}}
                                    ]
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440005",
                                    "created_at": "2024-01-23T11:45:00Z",
                                    "bpm": 110,
                                    "key": "E Minor",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "synth_lead",
                                "name": "Synth Lead",
                                "url": "https://example.com/samples/synth_lead.wav",
                                "is_public": True
                            },
                            {
                                "id": "synth_bass",
                                "name": "Synth Bass",
                                "url": "https://example.com/samples/synth_bass.wav",
                                "is_public": True
                            },
                            {
                                "id": "drum_retro",
                                "name": "Drum Retro",
                                "url": "https://example.com/samples/drum_retro.wav",
                                "is_public": False
                            }
                        ]
                    }
                ]
            },
            "collaborators": [
                {
                    "user_id": "550e8400-e29b-41d4-a716-446655440006",
                    "role": "editor",
                    "joined_at": "2024-01-24T10:15:00Z"
                }
            ],
            "tags": ["synthwave", "retro", "electronic"],
            "visibility": "public"
        },
        {
            "id": "660e8400-e29b-41d4-a716-446655440007",
            "user_id": "550e8400-e29b-41d4-a716-446655440006",
            "name": "Mix Masters Demo",
            "created": "2024-01-21T13:30:00Z",
            "lastmodified": "2024-01-22T09:45:00Z",
            "plays_num": 89,
            "forks_num": 12,
            "edit_lock": False,
            "parent_id": None,
            "audio": {
                "format": "mp3",
                "duration": 203.1,
                "sample_rate": 44100,
                "channels": 2,
                "url": "https://example.com/audio/660e8400-e29b-41d4-a716-446655440007.mp3",
                "renders": [
                    {
                        "id": "render_007",
                        "url": "https://example.com/audio/renders/660e8400-e29b-41d4-a716-446655440007_render_007.mp3",
                        "created_at": "2024-01-22T09:45:00Z",
                        "version": "3.0",
                        "quality": "ultra"
                    }
                ],
                "sources": [
                    {
                        "scenes": [
                            {
                                "layers": [
                                    [
                                        {"id": "layer_091", "index": 0, "sample": {"sample_id": "kick_master", "sample_name": "Kick Mastered"}},
                                        {"id": "layer_092", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_093", "index": 2, "sample": {"sample_id": "kick_master", "sample_name": "Kick Mastered"}},
                                        {"id": "layer_094", "index": 3, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_095", "index": 4, "sample": {"sample_id": "kick_master", "sample_name": "Kick Mastered"}},
                                        {"id": "layer_096", "index": 5, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_097", "index": 6, "sample": {"sample_id": "kick_master", "sample_name": "Kick Mastered"}},
                                        {"id": "layer_098", "index": 7, "sample": {"sample_id": None, "sample_name": None}}
                                    ],
                                    [
                                        {"id": "layer_099", "index": 0, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_100", "index": 1, "sample": {"sample_id": "snare_master", "sample_name": "Snare Mastered"}},
                                        {"id": "layer_101", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_102", "index": 3, "sample": {"sample_id": "snare_master", "sample_name": "Snare Mastered"}},
                                        {"id": "layer_103", "index": 4, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_104", "index": 5, "sample": {"sample_id": "snare_master", "sample_name": "Snare Mastered"}},
                                        {"id": "layer_105", "index": 6, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_106", "index": 7, "sample": {"sample_id": "snare_master", "sample_name": "Snare Mastered"}}
                                    ],
                                    [
                                        {"id": "layer_107", "index": 0, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_108", "index": 1, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_109", "index": 2, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_110", "index": 3, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_111", "index": 4, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_112", "index": 5, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_113", "index": 6, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}},
                                        {"id": "layer_114", "index": 7, "sample": {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}}
                                    ],
                                    [
                                        {"id": "layer_115", "index": 0, "sample": {"sample_id": "bass_master", "sample_name": "Bass Mastered"}},
                                        {"id": "layer_116", "index": 1, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_117", "index": 2, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_118", "index": 3, "sample": {"sample_id": "bass_master", "sample_name": "Bass Mastered"}},
                                        {"id": "layer_119", "index": 4, "sample": {"sample_id": "bass_master", "sample_name": "Bass Mastered"}},
                                        {"id": "layer_120", "index": 5, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_121", "index": 6, "sample": {"sample_id": None, "sample_name": None}},
                                        {"id": "layer_122", "index": 7, "sample": {"sample_id": "bass_master", "sample_name": "Bass Mastered"}}
                                    ]
                                ],
                                "metadata": {
                                    "user": "550e8400-e29b-41d4-a716-446655440006",
                                    "created_at": "2024-01-21T13:30:00Z",
                                    "bpm": 128,
                                    "key": "C Minor",
                                    "time_signature": "4/4"
                                }
                            }
                        ],
                        "samples": [
                            {
                                "id": "kick_master",
                                "name": "Kick Mastered",
                                "url": "https://example.com/samples/kick_master.wav",
                                "is_public": True
                            },
                            {
                                "id": "snare_master",
                                "name": "Snare Mastered",
                                "url": "https://example.com/samples/snare_master.wav",
                                "is_public": True
                            },
                            {
                                "id": "hihat_master",
                                "name": "Hi-Hat Mastered",
                                "url": "https://example.com/samples/hihat_master.wav",
                                "is_public": True
                            },
                            {
                                "id": "bass_master",
                                "name": "Bass Mastered",
                                "url": "https://example.com/samples/bass_master.wav",
                                "is_public": False
                            }
                        ]
                    }
                ]
            },
            "collaborators": [],
            "tags": ["mixing", "demo", "professional"],
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