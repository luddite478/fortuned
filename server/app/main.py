# main.py
import sys
import os
import threading
import asyncio
import uvicorn
from fastapi import FastAPI
import logging

current_dir = os.path.dirname(__file__)
sys.path.insert(0, current_dir)

from http_api.router import router as api_router
from ws.router import start_websocket_server

# Import database initialization
from db.init_collections import init_mongodb

from dotenv import load_dotenv
# Load .env from the server directory (parent of app directory)
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Debug: Print loaded API_TOKEN
api_token = os.getenv("API_TOKEN")
logger.info(f"🔑 Server loaded API_TOKEN: {api_token}")

app = FastAPI(
    title="API",
    version="0.0.1"
)

# Include API routes under /api/v1 prefix
app.include_router(api_router, prefix="/api/v1", tags=["API v1"])

def run_ws_server():
    asyncio.run(start_websocket_server())

def init_database():
    """Initialize database collections"""
    try:
        logger.info("🗄️  Initializing database...")
        
        # For testing, always reinitialize database
        logger.info("🔄 Reinitializing database (drop existing collections)")
        init_mongodb(drop_existing=True, insert_samples=True)
            
    except Exception as e:
        logger.error(f"❌ Database initialization failed: {e}")
        # Don't crash the server, just log the error
        logger.warning("⚠️  Server starting without database initialization")

@app.on_event("startup")
def startup_event():
    # Initialize database first
    init_database()
    
    # Then start websocket server
    ws_thread = threading.Thread(target=run_ws_server, daemon=True)
    ws_thread.start()
    
    logger.info("🚀 Server startup complete!")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
