#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-lowercase-last: lofi-lowercase over the agent's final message only.
next to lofi-lowercase, shows whether the style wears off by the end of a
long run.
"""
from _lib import *

emit(lambda: lowercase_score("last"))
