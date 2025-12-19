#!/usr/bin/env python3
# spellchecker: ignore dmenu 
# spellchecker: ignore Marcin Konowalczyk lczyk
#
# A script to handle choosing wallpapers based on usage frequency.
# Usage:
#   wallpaper_handler.py [wallpaper1 wallpaper2 ...]
#
# Written by Marcin Konowalczyk @lczyk 2025
# License: MIT-0

import argparse
import os
import sys
import sqlite3
import random

_DB_PATH = os.path.expanduser("~/.local/share/wallpaper_handler/wallpapers.db")

INIT_COUNT_BIAS = 5  # initial count bias for new wallpapers

_debug = False

def debug(*args: object, **kwargs: object) -> None:
    if _debug:
        kwargs.pop("file", None)
        print("[DEBUG]", *args, file=sys.stderr, **kwargs)  # type: ignore

def sample(weights: list[float]) -> int:
    total = sum(weights)
    r = random.uniform(0, total)
    cumulative: float = 0
    for i, w in enumerate(weights):
        cumulative += w
        if r < cumulative:
            return i
    return len(weights) - 1  # Fallback


def main():
    # for now just pass everything to stdout
    args = parse_args()
    if args.debug:
        global _debug
        _debug = True

    if args.command == "clean":
        if os.path.exists(_DB_PATH):
            os.remove(_DB_PATH)
            debug("Database cleaned.")
        else:
            debug("No database to clean.")
        return
    elif args.command == "select":

        if not args.choices:
            debug("no wallpapers provided")
            return
        
        os.makedirs(os.path.dirname(_DB_PATH), exist_ok=True)
        conn = sqlite3.connect(_DB_PATH)
        
        c = conn.cursor()
        
        # Initialize the database if it doesn't exist
        c.execute("""
            CREATE TABLE IF NOT EXISTS wallpapers (
                id INTEGER PRIMARY KEY,
                path TEXT UNIQUE,
                count INTEGER DEFAULT 0
            )
        """)

        # create a meta table to store last selected wallpaper
        c.execute("""
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        # Get the average count of all wallpapers
        c.execute("SELECT AVG(count) FROM wallpapers")
        avg_count = c.fetchone()[0] or 0
        debug("Average count of wallpapers:", avg_count)

        # Record all the wallpapers if they are not already in the database
        # initialize with average count to avoid too much bias towards new wallpapers 
        init_count = max(int(avg_count) - INIT_COUNT_BIAS, 0)
        debug("Initial count for new wallpapers:", init_count)
        for choice in args.choices:
            c.execute(
                "INSERT OR IGNORE INTO wallpapers (path, count) VALUES (?, ?)",
                (choice, init_count),
            )
        conn.commit()

        # Print all wallpapers and their counts for debugging
        if _debug:
            c.execute("SELECT path, count FROM wallpapers")
            wallpapers = c.fetchall()
            for path, count in wallpapers:
                debug(f" Wallpaper: {path}, Count: {count}")
        
        # Pick from a probability distribution based on counts. the less used, the higher chance.
        c.execute("SELECT path, count FROM wallpapers WHERE path IN ({})".format(",".join("?"*len(args.choices))), args.choices)
        wallpapers = c.fetchall()
        paths, counts = zip(*wallpapers)
        max_count = max(counts) if counts else 0
        weights = [max_count - count + 1 for count in counts]  # +1 to avoid zero weight
        debug("Weights:", weights)

        # Read the last selected wallpaper to avoid immediate repetition
        c.execute("SELECT value FROM meta WHERE key = ?", ("last_selected",))
        last_selected = c.fetchone()
        if last_selected:
            last_selected = last_selected[0]
            debug("Last selected wallpaper:", last_selected)
            if last_selected in paths:
                last_index = paths.index(last_selected)
                weights[last_index] = 0
                debug("Adjusted weights to avoid repetition:", weights)

        selected_index = sample(weights)
        selected_wallpaper = paths[selected_index]
        debug("Selected wallpaper:", selected_wallpaper)
        
        # Update the count for the selected wallpaper
        c.execute("UPDATE wallpapers SET count = count + 1 WHERE path = ?", (selected_wallpaper,))

        # Store the selected wallpaper in meta table
        c.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            ("last_selected", selected_wallpaper),
        )

        conn.commit()
        conn.close()
    
        # Print to stdout. Make sure we work with pipes.
        # https://docs.python.org/3/library/signal.html#note-on-sigpipe
        # spellchecker: ignore WRONLY
        try:
            print(selected_wallpaper)
            sys.stdout.flush()
        except BrokenPipeError:
            # Gracefully handle broken pipe when e.g. piping to head
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            sys.exit(1)

    elif args.command == "info":
        if not os.path.exists(_DB_PATH):
            print("No wallpaper database found.")
            return
        conn = sqlite3.connect(_DB_PATH)
        c = conn.cursor()
        c.execute("SELECT path, count FROM wallpapers ORDER BY count DESC")
        wallpapers = c.fetchall()
        for path, count in wallpapers:
            print(f"{count} {path}")
        conn.close()

    else:
        raise ValueError("Unknown command")


def parse_args():
    parser = argparse.ArgumentParser(description="Handle wallpaper choice.")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    _clean_subparser = subparsers.add_parser("clean", help="Clean the wallpaper database.")
    select_subparser = subparsers.add_parser("select", help="Select a wallpaper from the given choices.")
    select_subparser.add_argument(
        "choices",
        nargs="*",
        help="List of paths to wallpapers.",
    )
    _info_subparser = subparsers.add_parser("info", help="Show wallpaper usage info.")
    args = parser.parse_args()

    return args


if __name__ == "__main__":
    main()
