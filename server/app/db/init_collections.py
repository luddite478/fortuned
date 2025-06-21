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
    "soundseries": [
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "kick_01", "sample_name": "Kick Basic"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_01", "sample_name": "Kick Basic"},
                                        {"sample_id": null, "sample_name": null}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_01", "sample_name": "Snare Tight"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_01", "sample_name": "Snare Tight"}
                                    ],
                                    [
                                        {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"},
                                        {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"},
                                        {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"},
                                        {"sample_id": "hihat_01", "sample_name": "Hi-Hat Closed"}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "bass_01", "sample_name": "Bass Deep"},
                                        {"sample_id": null, "sample_name": null}
                                    ]
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
                                "is_public": true
                            },
                            {
                                "id": "snare_01",
                                "name": "Snare Tight",
                                "url": "https://example.com/samples/snare_01.wav",
                                "is_public": true
                            },
                            {
                                "id": "hihat_01",
                                "name": "Hi-Hat Closed",
                                "url": "https://example.com/samples/hihat_01.wav",
                                "is_public": true
                            },
                            {
                                "id": "bass_01",
                                "name": "Bass Deep",
                                "url": "https://example.com/samples/bass_01.wav",
                                "is_public": false
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "kick_02", "sample_name": "Kick Heavy"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_02", "sample_name": "Kick Heavy"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_02", "sample_name": "Kick Heavy"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_02", "sample_name": "Kick Heavy"},
                                        {"sample_id": null, "sample_name": null}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_02", "sample_name": "Snare Clap"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_02", "sample_name": "Snare Clap"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_02", "sample_name": "Snare Clap"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_02", "sample_name": "Snare Clap"}
                                    ],
                                    [
                                        {"sample_id": "bass_02", "sample_name": "Bass Drop"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "bass_02", "sample_name": "Bass Drop"},
                                        {"sample_id": "bass_02", "sample_name": "Bass Drop"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "bass_02", "sample_name": "Bass Drop"}
                                    ]
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
                                "is_public": true
                            },
                            {
                                "id": "snare_02",
                                "name": "Snare Clap",
                                "url": "https://example.com/samples/snare_02.wav",
                                "is_public": true
                            },
                            {
                                "id": "bass_02",
                                "name": "Bass Drop",
                                "url": "https://example.com/samples/bass_02.wav",
                                "is_public": false
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "kick_03", "sample_name": "Kick Experimental"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_03", "sample_name": "Kick Experimental"}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "perc_01", "sample_name": "Perc Weird"},
                                        {"sample_id": null, "sample_name": null}
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
                                "is_public": false
                            },
                            {
                                "id": "perc_01",
                                "name": "Perc Weird",
                                "url": "https://example.com/samples/perc_01.wav",
                                "is_public": true
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"},
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"},
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"},
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"},
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"},
                                        {"sample_id": "pad_01", "sample_name": "Pad Ambient"}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "texture_01", "sample_name": "Texture Soft"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "texture_01", "sample_name": "Texture Soft"}
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
                                "is_public": true
                            },
                            {
                                "id": "texture_01",
                                "name": "Texture Soft",
                                "url": "https://example.com/samples/texture_01.wav",
                                "is_public": true
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "kick_lofi", "sample_name": "Kick Lo-fi"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_lofi", "sample_name": "Kick Lo-fi"}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_lofi", "sample_name": "Snare Dusty"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_lofi", "sample_name": "Snare Dusty"}
                                    ],
                                    [
                                        {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"},
                                        {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"},
                                        {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"},
                                        {"sample_id": "vinyl_01", "sample_name": "Vinyl Crackle"}
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
                                "is_public": true
                            },
                            {
                                "id": "snare_lofi",
                                "name": "Snare Dusty",
                                "url": "https://example.com/samples/snare_lofi.wav",
                                "is_public": true
                            },
                            {
                                "id": "vinyl_01",
                                "name": "Vinyl Crackle",
                                "url": "https://example.com/samples/vinyl_01.wav",
                                "is_public": false
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "synth_lead", "sample_name": "Synth Lead"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "synth_lead", "sample_name": "Synth Lead"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "synth_lead", "sample_name": "Synth Lead"},
                                        {"sample_id": null, "sample_name": null}
                                    ],
                                    [
                                        {"sample_id": "synth_bass", "sample_name": "Synth Bass"},
                                        {"sample_id": "synth_bass", "sample_name": "Synth Bass"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "synth_bass", "sample_name": "Synth Bass"},
                                        {"sample_id": "synth_bass", "sample_name": "Synth Bass"},
                                        {"sample_id": null, "sample_name": null}
                                    ],
                                    [
                                        {"sample_id": "drum_retro", "sample_name": "Drum Retro"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "drum_retro", "sample_name": "Drum Retro"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "drum_retro", "sample_name": "Drum Retro"},
                                        {"sample_id": null, "sample_name": null}
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
                                "is_public": true
                            },
                            {
                                "id": "synth_bass",
                                "name": "Synth Bass",
                                "url": "https://example.com/samples/synth_bass.wav",
                                "is_public": true
                            },
                            {
                                "id": "drum_retro",
                                "name": "Drum Retro",
                                "url": "https://example.com/samples/drum_retro.wav",
                                "is_public": false
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
                        "grid_stacks": [
                            {
                                "layers": [
                                    [
                                        {"sample_id": "kick_master", "sample_name": "Kick Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_master", "sample_name": "Kick Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_master", "sample_name": "Kick Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "kick_master", "sample_name": "Kick Mastered"},
                                        {"sample_id": null, "sample_name": null}
                                    ],
                                    [
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_master", "sample_name": "Snare Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_master", "sample_name": "Snare Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_master", "sample_name": "Snare Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "snare_master", "sample_name": "Snare Mastered"}
                                    ],
                                    [
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"},
                                        {"sample_id": "hihat_master", "sample_name": "Hi-Hat Mastered"}
                                    ],
                                    [
                                        {"sample_id": "bass_master", "sample_name": "Bass Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "bass_master", "sample_name": "Bass Mastered"},
                                        {"sample_id": "bass_master", "sample_name": "Bass Mastered"},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": null, "sample_name": null},
                                        {"sample_id": "bass_master", "sample_name": "Bass Mastered"}
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
                                "is_public": true
                            },
                            {
                                "id": "snare_master",
                                "name": "Snare Mastered",
                                "url": "https://example.com/samples/snare_master.wav",
                                "is_public": true
                            },
                            {
                                "id": "hihat_master",
                                "name": "Hi-Hat Mastered",
                                "url": "https://example.com/samples/hihat_master.wav",
                                "is_public": true
                            },
                            {
                                "id": "bass_master",
                                "name": "Bass Mastered",
                                "url": "https://example.com/samples/bass_master.wav",
                                "is_public": false
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