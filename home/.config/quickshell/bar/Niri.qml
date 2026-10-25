pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Thin niri IPC wrapper: re-queries state whenever the event stream says something changed.
Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property string title: ""
    property string appId: ""

    function byOutput(name) {
        return workspaces.filter(w => w.output === name);
    }
    function windowsOn(wsId) {
        return windows.filter(w => w.workspace_id === wsId);
    }
    function focusWorkspace(idx) {
        run.command = ["niri", "msg", "action", "focus-workspace", String(idx)];
        run.running = true;
    }
    function refresh() {
        wsProc.running = true;
        allWinProc.running = true;
        winProc.running = true;
    }

    Process { id: run }

    Process {
        id: wsProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(text).sort((a, b) => a.idx - b.idx);
                } catch (e) {}
            }
        }
    }
    Process {
        id: allWinProc
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.windows = JSON.parse(text); } catch (e) {}
            }
        }
    }
    Process {
        id: winProc
        command: ["niri", "msg", "-j", "focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    root.title = w ? (w.title || "") : "";
                    root.appId = w ? (w.app_id || "") : "";
                } catch (e) {
                    root.title = "";
                    root.appId = "";
                }
            }
        }
    }
    Process {
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
    }
    Timer {
        id: debounce
        interval: 30
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
