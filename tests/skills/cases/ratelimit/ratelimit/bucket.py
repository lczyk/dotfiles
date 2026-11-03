"""Fixed-window rate limiter."""
import time


class RateLimiter:
    """Allow at most `limit` calls per `window_s` seconds."""

    def __init__(self, limit, window_s, clock=time.monotonic):
        self.limit = limit
        self.window_s = window_s
        self.clock = clock
        self.window_start = clock()
        self.count = 0

    def allow(self):
        now = self.clock()
        if now - self.window_start > self.window_s:
            self.window_start = now
            self.count = 0
        if self.count <= self.limit:
            self.count += 1
            return True
        return False
