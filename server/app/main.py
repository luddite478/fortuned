# main.py
import threading
import asyncio
import uvicorn
from fastapi import FastAPI

from http_api.router import router
from websockets import router as ws_module

from dotenv import load_dotenv
load_dotenv()

app = FastAPI()
app.include_router(router)

def run_ws_server():
    asyncio.run(ws_module.main())

@app.on_event("startup")
def startup_event():
    ws_thread = threading.Thread(target=run_ws_server, daemon=True)
    ws_thread.start()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
