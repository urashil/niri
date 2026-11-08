pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keeps ~/.config/rice/launcher-shortcuts.json mirrored into .desktop entries (via
// rice-shortcuts-gen) so custom shortcuts like "school" show up in the launcher by name.
Singleton {
    id: root

    function regenerate(): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rice-shortcuts-gen"]);
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/launcher-shortcuts.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.regenerate()
    }

    Component.onCompleted: regenerate()
}
