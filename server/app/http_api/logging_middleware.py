import sys
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
import time
import traceback

# Configure logger
logger = logging.getLogger(__name__)

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        
        try:
            response = await call_next(request)
            process_time = (time.time() - start_time) * 1000
            
            logger.info(
                f"Processed request: {request.method} {request.url.path} - "
                f"Completed {response.status_code} in {process_time:.2f}ms"
            )
            
            return response
            
        except Exception as e:
            process_time = (time.time() - start_time) * 1000
            
            # Format traceback
            tb_str = traceback.format_exc()
            
            logger.error(
                f"Error processing request: {request.method} {request.url.path} - "
                f"Error: {e} - Took {process_time:.2f}ms\n"
                f"Traceback:\n{tb_str}"
            )
            
            # Re-raise the exception to let FastAPI handle the 500 response
            raise
