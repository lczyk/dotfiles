import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// NOTE: opacity is 0-255. mirrors sway opacity.py: active 0.95, inactive 0.85.
// hardcoded -- edit here if you want different values, not worth a settings schema.
const ACTIVE = Math.round(0.95 * 255);   // 242
const INACTIVE = Math.round(0.85 * 255); // 217

export default class FocusOpacityExtension extends Extension {
    enable() {
        const d = global.display;
        this._ids = [
            d.connect('notify::focus-window', () => this._update()),
            // new windows: defer one tick so their actor exists before we set opacity
            d.connect('window-created', () => this._defer()),
        ];
        this._update();
    }

    disable() {
        for (const id of this._ids ?? [])
            global.display.disconnect(id);
        this._ids = null;
        if (this._timeout) {
            clearTimeout(this._timeout);
            this._timeout = null;
        }
        for (const a of global.get_window_actors())
            a.opacity = 255; // restore on unload
    }

    _defer() {
        // window-created fires before the actor is mapped; settle on next loop turn
        this._timeout = setTimeout(() => {
            this._timeout = null;
            this._update();
        }, 0);
    }

    _update() {
        const focus = global.display.focus_window;
        for (const actor of global.get_window_actors())
            actor.opacity = actor.meta_window === focus ? ACTIVE : INACTIVE;
    }
}
