#!/usr/bin/env python3
# spellchecker: ignore dmenu 
# spellchecker: ignore Marcin Konowalczyk lczyk
#
# A script to handle recording and sorting choices from dmenu_path.
# It uses a simple sqlite database to store the choices and their counts.
# Usage:
#   To record a choice:
#     launcher_handler.py record <choice>
#   To list choices sorted by count:
#     launcher_handler.py list [--counts] [choices...]
#
# Written by Marcin Konowalczyk @lczyk 2025
# License: MIT-0

import argparse
import os
import sys
import sqlite3

_DB_PATH = os.path.expanduser("~/.local/share/launcher_handler/choices.db")


def main():
    # for now just pass everything to stdout
    args = parse_args()
    if args.command == "record":
        # print(f"Recording choice: {args.choice}", file=sys.stderr)
        if args.choice:
            os.makedirs(os.path.dirname(_DB_PATH), exist_ok=True)
            conn = sqlite3.connect(_DB_PATH)
            c = conn.cursor()
            c.execute("""
                CREATE TABLE IF NOT EXISTS choices (
                    id INTEGER PRIMARY KEY,
                    choice TEXT UNIQUE,
                    count INTEGER DEFAULT 0
                )
            """)
            c.execute(
                """
                INSERT INTO choices (choice, count)
                VALUES (?, 1)
                ON CONFLICT(choice) DO UPDATE SET count = count + 1
            """,
                (args.choice,),
            )
            conn.commit()
            conn.close()

    elif args.command == "list":
        # print(f"Listing choices: {args.choices}", file=sys.stderr)
        if not args.choices:
            out = ""
        else:
            choices_and_counts = [(choice, 0) for choice in args.choices]
            if os.path.exists(_DB_PATH):
                # get all the counts from the db as (choice, count) tuples
                conn = sqlite3.connect(_DB_PATH)
                c = conn.cursor()
                c.execute("SELECT choice, count FROM choices")
                db_counts = dict(c.fetchall())
                conn.close()

                # update counts from db
                choices_and_counts = [
                    (choice, db_counts.get(choice, 0)) for choice in args.choices
                ]
            # sort by count desc, then alphabetically
            choices_and_counts.sort(key=lambda x: (-x[1], x[0].lower()))
            if args.counts:
                out = "\n".join(
                    f"{choice} ({count})" for choice, count in choices_and_counts
                )
            else:
                out = "\n".join(choice for choice, _count in choices_and_counts)

        # Print to stdout. Make sure we work with pipes.
        # https://docs.python.org/3/library/signal.html#note-on-sigpipe
        # spellchecker: ignore WRONLY
        try:
            print(out)
            sys.stdout.flush()
        except BrokenPipeError:
            # Gracefully handle broken pipe when e.g. piping to head
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            sys.exit(1)
    else:
        raise ValueError("Unknown command")


def parse_args():
    parser = argparse.ArgumentParser(description="Handle dmenu path selection.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    list_parser = subparsers.add_parser("list", help="Sort and output choices.")
    list_parser.add_argument("choices", nargs="*", help="Output of dmenu_path")
    list_parser.add_argument(
        "--counts", action="store_true", help="Show counts next to choices."
    )
    record_parser = subparsers.add_parser("record", help="Record a choice.")
    record_parser.add_argument("choice", help="The choice to record.")
    args = parser.parse_args()

    if args.command == "list":
        args.choices = list(set(args.choices))
    elif args.command == "record":
        if not args.choice:
            args.choice = None

    return args


if __name__ == "__main__":
    main()
