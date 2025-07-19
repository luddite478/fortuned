import time
from collections import defaultdict
from fastapi import Request, HTTPException
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import logging

logger = logging.getLogger(__name__)

MAX_REQUESTS_PER_MINUTE = 120

# In-memory rate limiting storage
rate_limit_data = defaultdict(lambda: {"count": 0, "reset_time": time.time() + 60})

# Endpoints that should be exempt from rate limiting
RATE_LIMIT_EXEMPT_PATHS = {
}

class RateLimitMiddleware(BaseHTTPMiddleware):
    """Middleware to apply rate limiting to all requests"""
    
    async def dispatch(self, request: Request, call_next):
        # Skip rate limiting for exempt paths
        if request.url.path in RATE_LIMIT_EXEMPT_PATHS:
            return await call_next(request)
        
        # Apply rate limiting
        try:
            self._check_rate_limit(request)
        except HTTPException as e:
            logger.warning(f"Rate limit exceeded for IP: {request.client.host}")
            return JSONResponse(
                status_code=e.status_code,
                content={"detail": e.detail}
            )
        
        # Continue with the request
        return await call_next(request)
    
    def _check_rate_limit(self, request: Request):
        """Check rate limit for the requesting IP"""
        ip = request.client.host
        now = time.time()
        record = rate_limit_data[ip]

        # Reset counter if time window has passed
        if now > record["reset_time"]:
            record["count"] = 0
            record["reset_time"] = now + 60

        # Check if rate limit is exceeded
        if record["count"] >= MAX_REQUESTS_PER_MINUTE:
            raise HTTPException(
                status_code=429, 
                detail="Rate limit exceeded. Try again later."
            )

        # Increment request count
        record["count"] += 1

# Legacy function for backward compatibility (will be removed)
def check_rate_limit(request: Request):
    """Legacy function - rate limiting is now handled by middleware"""
    # This function is kept for transition period but does nothing
    # All rate limiting is now handled by RateLimitMiddleware
    pass
