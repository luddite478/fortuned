import sys
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
import time

# Configure logger
logger = logging.getLogger(__name__)

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        
        response = await call_next(request)
        
        process_time = (time.time() - start_time) * 1000
        
        logger.info(
            f"Processed request: {request.method} {request.url.path} - "
            f"Completed {response.status_code} in {process_time:.2f}ms"
        )
        
        return response
