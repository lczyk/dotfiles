import GLib from 'gi://GLib';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// enhances gnome 50's native panel workspace dots (.workspace-dot, inside the
// Activities button) so occupied workspaces stand out from empty ones. no
// second indicator -- we just tag the existing dots and let css colour them.

export default class WorkspaceOccupancyExtension extends Extension {
    enable() {
        const wm = global.workspace_manager;
        const d = global.display;
        const wmgr = global.window_manager;
        const q = () => this._queue();
        this._conns = [
            [wm, wm.connect('notify::n-workspaces', q)],
            [wm, wm.connect('active-workspace-changed', q)],
            [d, d.connect('window-created', q)],          // opens
            [wmgr, wmgr.connect('destroy', q)],           // closes
            [wmgr, wmgr.connect('switch-workspace', q)],  // moves
        ];
        this._queue();
    }

    // NOTE: 250ms debounce -- the native dots are added/removed async (scaleIn /
    // scaleOutAndDestroy), so we settle after the burst before re-tagging.
    _queue() {
        if (this._timeout)
            return;
        this._timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
            this._timeout = 0;
            this._tag();
            return GLib.SOURCE_REMOVE;
        });
    }

    // collect the inner '.workspace-dot' St.Widgets in tree order (== workspace
    // order). they're St.Widget (the outer WorkspaceDot is a bare Clutter.Actor
    // with no style methods), so we colour these directly.
    _dots() {
        const act = Main.panel.statusArea.activities;
        if (!act)
            return [];
        const out = [];
        const walk = a => {
            if ((a.style_class ?? '').includes('workspace-dot'))
                out.push(a);
            for (const c of a.get_children?.() ?? [])
                walk(c);
        };
        walk(act);
        return out;
    }

    _tag() {
        const dots = this._dots();
        const wm = global.workspace_manager;
        const n = Math.min(dots.length, wm.get_n_workspaces());
        for (let i = 0; i < n; i++) {
            const ws = wm.get_workspace_by_index(i);
            // ignore sticky/on-all-workspaces windows (wallpaper, desktop icons)
            // and skip-taskbar ones (docks) -- they show on every workspace.
            const occupied = ws && ws.list_windows().some(
                w => !w.is_on_all_workspaces() && !w.skip_taskbar);
            // inline style beats the theme rule, no specificity fight.
            dots[i].set_style(occupied ? 'background-color: #4a9eff;' : null);
        }
    }

    disable() {
        for (const [obj, id] of this._conns ?? [])
            obj.disconnect(id);
        this._conns = null;
        if (this._timeout) {
            GLib.source_remove(this._timeout);
            this._timeout = 0;
        }
        for (const dot of this._dots())
            dot.set_style(null); // restore theme colour
    }
}
