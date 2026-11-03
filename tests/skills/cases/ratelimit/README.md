# ratelimit

A tiny fixed-window rate limiter.

```python
from ratelimit.bucket import RateLimiter

rl = RateLimiter(limit=10, window_s=60)
if rl.allow():
    handle(request)
```
