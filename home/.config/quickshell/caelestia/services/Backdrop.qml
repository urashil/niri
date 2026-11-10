pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Keeps the niri overview backdrop (painted by `awww-daemon --namespace backdrop`) in sync with
// caelestia's current wallpaper, so the overview matches the desktop when the wallpaper changes.
Singleton {
    id: root

    function sync(): void {
        const w = String(Wallpapers.actualCurrent || "").replace(/^file:\/\//, "");
        if (w.length)
            Quickshell.execDetached(["awww", "img", "--namespace", "backdrop", "--all", w, "--transition-type", "none"]);
    }

    Connections {
        target: Wallpapers
        function onActualCurrentChanged(): void { root.sync(); }
    }

    Component.onCompleted: sync()
}
