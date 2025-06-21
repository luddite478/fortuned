# main.py
import sys
import os
import threading
import asyncio
import uvicorn
from fastapi import FastAPI

current_dir = os.path.dirname(__file__)
sys.path.insert(0, current_dir)

from http_api.router import router
from ws.router import start_websocket_server

from dotenv import load_dotenv
load_dotenv()

app = FastAPI()
app.include_router(router)

def run_ws_server():
    asyncio.run(start_websocket_server())

@app.on_event("startup")
def startup_event():
    ws_thread = threading.Thread(target=run_ws_server, daemon=True)
    ws_thread.start()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
