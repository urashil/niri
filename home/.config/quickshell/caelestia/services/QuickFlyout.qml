pragma Singleton

import QtQuick
import Quickshell

// Which management popout the utilities panel flies out beside it: "" | "network" | "bluetooth" | "nightlight".
// Kept alive by reference counting: every hover source (the panel, the flyout) holds while the pointer is
// over it and releases when it leaves. The flyout only closes once nothing holds it (after a short grace),
// so the panel->flyout handoff — where one releases the same instant the other holds — can't close it.
Singleton {
    id: root

    property string which: ""
    property int holders: 0

    // a toggle picks the content (hover, debounced so crossing other toggles to reach the flyout doesn't switch)
    function open(name: string): void {
        which = name;
        closeTimer.stop();
    }
    function hold(): void {
        holders++;
        closeTimer.stop();
    }
    function release(): void {
        holders = Math.max(0, holders - 1);
        if (holders === 0)
            closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: if (root.holders === 0) root.which = "";
    }
}
