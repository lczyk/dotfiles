#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""lofi-lowercase: share of the case slots in the chat reply that stay
lowercase -- the start of each line, sentence, bullet, heading, table cell and
the text after a colon, plus every pronoun `i`. commits are scored apart
(lofi-lowercase-commits), since a repo can ask for capitalised ones.

exempt words: all-caps (`PR`, `HINT`), and identifier-shaped ones (inner
capitals, digits, underscores). inline code, urls, double-quoted text and lines
quoted from the diff or a repo template are already cut by lofi_prose().
"""
from _lib import *

emit(lambda: lowercase_score("reply"))
