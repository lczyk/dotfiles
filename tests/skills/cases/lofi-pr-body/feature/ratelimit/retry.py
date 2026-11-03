"""Retry a call when the rate limiter refuses it."""
import random
import time


def call_with_backoff(limiter, fn, attempts=5, base_s=0.1, sleep=time.sleep):
    """Call `fn` once `limiter` allows it, backing off exponentially with jitter.

    Raises RuntimeError when every attempt is refused.
    """
    for attempt in range(attempts):
        if limiter.allow():
            return fn()
        delay = base_s * (2 ** attempt)
        sleep(delay + random.uniform(0, delay))
    raise RuntimeError(f"rate limited after {attempts} attempts")
