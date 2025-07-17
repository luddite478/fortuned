#!/usr/bin/env python3
"""
Sample Scanner with Hash Generation
Scans the samples directory and generates unique hashes for each audio file
"""

import os
import hashlib
import json
import time
from pathlib import Path
from typing import Dict, List, Any

# Supported audio file extensions
AUDIO_EXTENSIONS = {'.wav', '.mp3', '.aiff', '.aif', '.flac', '.ogg', '.m4a'}

def generate_file_hash(file_path: Path) -> str:
    """Generate SHA-256 hash for a file"""
    hash_sha256 = hashlib.sha256()
    
    try:
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_sha256.update(chunk)
        return hash_sha256.hexdigest()
    except Exception as e:
        print(f"Error hashing file {file_path}: {e}")
        return ""

def scan_samples_directory(samples_dir: str = "samples") -> Dict[str, Any]:
    """Scan the samples directory and generate hashes for all audio files"""
    samples_dir_path = Path(samples_dir)
    
    if not samples_dir_path.exists():
        print(f"Samples directory '{samples_dir}' not found!")
        return {}
    
    samples_data = {
        "scan_timestamp": int(time.time()),
        "total_files": 0,
        "samples": {}
    }
    
    print(f"Scanning samples directory: {samples_dir_path.absolute()}")
    
    for root, dirs, files in os.walk(samples_dir_path):
        root_path = Path(root)
        audio_files = [f for f in files if Path(f).suffix.lower() in AUDIO_EXTENSIONS]
        
        if not audio_files:
            continue
            
        relative_path = root_path.relative_to(samples_dir_path)
                
        for filename in audio_files:
            file_path = root_path / filename
            print(f"  Hashing: {filename}...")
            
            file_hash = generate_file_hash(file_path)
            if not file_hash:
                continue
                
            sample_id = f"{file_hash[:12]}"
            relative_file_path = str(file_path)
            
            sample_entry = {
                "path": relative_file_path,
                "built_in": True
            }
            
            samples_data["samples"][sample_id] = sample_entry
            samples_data["total_files"] += 1
    
    print(f"Scan complete! Found {samples_data['total_files']} audio files.")
    return samples_data

def save_samples_manifest(samples_data: Dict[str, Any], output_file: str = "samples_manifest.json"):
    """Save the samples data to a JSON file"""
    try:
        with open(output_file, 'w') as f:
            json.dump(samples_data, f, indent=2)
        print(f"Samples manifest saved to: {output_file}")
    except Exception as e:
        print(f"Error saving manifest: {e}")

if __name__ == "__main__":
    samples_data = scan_samples_directory("samples")
    if samples_data:
        save_samples_manifest(samples_data, "samples_manifest.json")
