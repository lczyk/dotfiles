#!/usr/bin/env python3
# based on https://github.com/nwg-piotr/autotiling
# copyright 2019-2021 Piotr Miller & Contributors
# this file is licensed under GPL-3.0-or-later (see LICENSE)

import argparse
import sys
from functools import partial

from i3ipc import Connection, Event


def output_name(con):
    if con.type == "root":
        return None
    if p := con.parent:
        return p.name if p.type == "output" else output_name(p)


def switch_splitting(i3, e, *, debug, outputs, workspaces, depth_limit, splitratio):
    try:
        con = i3.get_tree().find_focused()
        if con is None:
            return

        if outputs:
            output = output_name(con)
            if output not in outputs:
                if debug:
                    print(f"autotiling off on output {output}", file=sys.stderr)
                return

        if workspaces and str(con.workspace().num) not in workspaces:
            if debug:
                print("autotiling off on this workspace", file=sys.stderr)
            return

        if con.floating:
            is_floating = "_on" in con.floating  # i3
        else:
            is_floating = con.type == "floating_con"  # sway

        if depth_limit:
            depth_limit_reached = True
            cur = con
            depth = 0
            while depth < depth_limit:
                if cur.type == "workspace":
                    depth_limit_reached = False
                    break
                cur = cur.parent
                if len(cur.nodes) > 1:
                    depth += 1
            if depth_limit_reached:
                if debug:
                    print("depth limit reached", file=sys.stderr)
                return

        if (
            is_floating
            or con.fullscreen_mode == 1
            or con.parent.layout in ("stacked", "tabbed")
        ):
            return

        new_layout = "splitv" if con.rect.height > con.rect.width / splitratio else "splith"
        if new_layout != con.parent.layout:
            result = i3.command(new_layout)
            if debug:
                if result[0].success:
                    print(f"switched to {new_layout}", file=sys.stderr)
                else:
                    print(f"switch failed: {result[0].error}", file=sys.stderr)

    except Exception as ex:
        print(f"error: {ex}", file=sys.stderr)


def main():
    p = argparse.ArgumentParser(
        prog="autotiling",
        description="automatically switch splith/splitv based on window dimensions",
    )
    p.add_argument("-d", "--debug", action="store_true")
    p.add_argument("-o", "--outputs", nargs="*", type=str, default=[])
    p.add_argument("-w", "--workspaces", nargs="*", type=str, default=[])
    p.add_argument("-l", "--limit", type=int, default=0)
    p.add_argument("-sr", "--splitratio", type=float, default=1.0)
    p.add_argument(
        "-e", "--events", nargs="*", type=str, default=["WINDOW", "MODE"],
        help="events to subscribe to (default: WINDOW MODE)",
    )
    args = p.parse_args()

    if not args.events:
        print("no events specified", file=sys.stderr)
        sys.exit(1)

    handler = partial(
        switch_splitting,
        debug=args.debug,
        outputs=args.outputs,
        workspaces=args.workspaces,
        depth_limit=args.limit,
        splitratio=args.splitratio,
    )

    i3 = Connection()
    for e in args.events:
        try:
            i3.on(Event[e], handler)
            if args.debug:
                print(f"subscribed to {Event[e]}", file=sys.stderr)
        except KeyError:
            print(f"unknown event: {e!r}", file=sys.stderr)

    i3.main()


if __name__ == "__main__":
    main()
