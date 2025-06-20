import time
from collections import defaultdict
from fastapi import Request, HTTPException

MAX_REQUESTS_PER_MINUTE = 60

rate_limit_data = defaultdict(lambda: {"count": 0, "reset_time": time.time() + 60})

def check_rate_limit(request: Request):
    ip = request.client.host
    now = time.time()
    record = rate_limit_data[ip]

    if now > record["reset_time"]:
        record["count"] = 0
        record["reset_time"] = now + 60

    if record["count"] >= MAX_REQUESTS_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Rate limit exceeded. Try again later.")

    record["count"] += 1
