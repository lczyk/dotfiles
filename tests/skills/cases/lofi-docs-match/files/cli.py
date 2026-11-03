"""Command-line front end for the rate limiter."""
import argparse
import logging
import sys

from ratelimit.bucket import RateLimiter


def main(argv=None):
    parser = argparse.ArgumentParser(description="Rate-limit lines read from stdin.")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--window", type=float, default=60.0)
    parser.add_argument("--verbose", action="store_true", help="log every dropped line to stderr")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING)
    rl = RateLimiter(limit=args.limit, window_s=args.window)
    for line in sys.stdin:
        if rl.allow():
            sys.stdout.write(line)
        else:
            logging.debug("dropped: %s", line.rstrip())


if __name__ == "__main__":
    main()
