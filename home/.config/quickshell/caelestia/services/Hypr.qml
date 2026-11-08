pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import Caelestia.Services
import qs.components.misc

// niri-backed drop-in for caelestia's Hyprland service.
// Caelestia is built for Hyprland; this host runs niri, so the workspace / window
// model is sourced from `niri msg` (JSON) and shaped to look like the Hyprland objects
// the rest of the shell reads (workspaces.values, toplevels.values, lastIpcObject.class,
// activeToplevel.title, monitor.activeWorkspace.id, …). Workspace "id" is the niri 1-based
// index, so focusWorkspace(id) maps straight to `niri msg action focus-workspace <id>`.
// Hyprland-only concepts (special workspaces, Lua dispatch, per-device keymaps) are stubbed.
Singleton {
    id: root

    // ---- raw niri state ----
    property var _wsRaw: []       // [{id, idx, name, output, is_active, is_focused}]
    property var _winRaw: []      // [{id, title, app_id, workspace_id, is_focused}]
    property var _focused: null   // focused-window object or null
    // signatures of the last applied state, so a chatty event-stream (or a window whose
    // title churns) doesn't rebuild the model and re-animate the bar when nothing structural changed
    property string _wsSig: ""
    property string _winSig: ""
    property string _focSig: ""

    // ---- built, Hyprland-shaped model (rebuilt on every niri change) ----
    property var _model: root._build()

    function _emptyWs(mon) {
        return {
            id: 1,
            name: "1",
            _wid: -1,
            monitor: mon,
            focused: true,
            active: true,
            activate: () => {},
            toplevels: {
                values: []
            },
            lastIpcObject: {
                windows: 0
            }
        };
    }

    function _build() {
        const wsRaw = _wsRaw || [];
        const winRaw = _winRaw || [];

        const idxById = {};
        for (const w of wsRaw)
            idxById[w.id] = w.idx;

        // toplevels (one per niri window); _wid is the internal niri workspace id
        const toplevels = winRaw.map(win => ({
            title: win.title || "",
            workspace: {
                id: idxById[win.workspace_id] ?? 0,
                _wid: win.workspace_id
            },
            monitor: null,
            wayland: null,
            activate: () => root._focusWindow(win.id),
            lastIpcObject: {
                class: win.app_id || "",
                mapped: true,
                tags: [],
                fullscreen: 0
            }
        }));

        // monitors, cached by name so identity comparisons hold (activeWorkspace filled below)
        const monByName = {};
        const monitors = [];
        for (const w of wsRaw) {
            if (monByName[w.output])
                continue;
            const m = {
                name: w.output,
                id: monitors.length + 1,
                activeWorkspace: null,
                lastIpcObject: {
                    specialWorkspace: {
                        name: ""
                    }
                }
            };
            monByName[w.output] = m;
            monitors.push(m);
        }

        // workspaces (reference their monitor)
        const workspaces = wsRaw.map(w => {
            const wsToplevels = toplevels.filter(t => t.workspace._wid === w.id);
            return {
                id: w.idx,
                name: w.name || String(w.idx),
                _wid: w.id,
                monitor: monByName[w.output] ?? null,
                focused: !!w.is_focused,
                active: !!w.is_active,
                activate: () => root.focusWorkspace(w.idx),
                toplevels: {
                    values: wsToplevels
                },
                lastIpcObject: {
                    windows: wsToplevels.length
                }
            };
        });

        // fill each monitor's active workspace with the full workspace object
        for (const m of monitors) {
            const raw = wsRaw.find(w => w.output === m.name && w.is_active);
            m.activeWorkspace = workspaces.find(w => raw && w._wid === raw.id) ?? root._emptyWs(m);
        }

        // guarantee at least one monitor so bindings like monitor.activeWorkspace never hit null
        if (monitors.length === 0) {
            const m = {
                name: "",
                id: 1,
                activeWorkspace: null,
                lastIpcObject: {
                    specialWorkspace: {
                        name: ""
                    }
                }
            };
            m.activeWorkspace = root._emptyWs(m);
            monByName[""] = m;
            monitors.push(m);
        }

        const focusedWs = workspaces.find(w => w.focused) ?? null;
        const focusedMon = (focusedWs && focusedWs.monitor) ? focusedWs.monitor : monitors[0];

        return {
            monByName,
            monitors: {
                values: monitors
            },
            workspaces: {
                values: workspaces
            },
            toplevels: {
                values: toplevels
            },
            focusedWs,
            focusedMon,
            activeWsId: focusedWs ? focusedWs.id : (focusedMon.activeWorkspace?.id ?? 1)
        };
    }

    // ---- public API (matches the Hyprland service surface the shell uses) ----
    readonly property var toplevels: _model.toplevels
    readonly property var workspaces: _model.workspaces
    readonly property var monitors: _model.monitors
    readonly property bool usingLua: false

    readonly property var activeToplevel: {
        const w = root._focused;
        if (!w || !w.title && !w.app_id)
            return null;
        return {
            title: w.title || "",
            workspace: {
                id: null
            },
            wayland: null,
            activate: () => root._focusWindow(w.id),
            lastIpcObject: {
                class: w.app_id || "",
                mapped: true,
                tags: [],
                fullscreen: 0
            }
        };
    }
    readonly property var focusedWorkspace: _model.focusedWs
    readonly property var focusedMonitor: _model.focusedMon
    readonly property int activeWsId: _model.activeWsId

    // keyboard (via HyprExtras — empty on niri, kept for API compatibility)
    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property string lastSpecialWorkspace: ""

    signal configReloaded

    function dispatch(request: string): void {
        // Hyprland dispatch has no niri equivalent; no-op.
    }

    function focusWorkspace(ws: var): void {
        root._run(["niri", "msg", "action", "focus-workspace", String(ws)]);
    }

    function _focusWindow(id: var): void {
        root._run(["niri", "msg", "action", "focus-window", "--id", String(id)]);
    }

    // special workspaces don't exist on niri
    function toggleSpecial(name: string): void {}
    function cycleSpecialWorkspace(direction: string): void {}

    function monitorNames(): list<string> {
        return _model.monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): var {
        if (!screen)
            return _model.focusedMon;
        return _model.monByName[screen.name] ?? _model.focusedMon;
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: int, ignoredTags = []): var {
        return _model.toplevels.values.filter(t => t.workspace && t.workspace.id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc?.class || !ipc.mapped)
            return true;
        return ipc.tags?.some(tag => ignoredTags.includes(tag.replace(/\*$/, ""))) ?? false;
    }

    function reloadDynamicConfs(): void {}

    // ---- niri IPC ----
    Process {
        id: runProc
    }
    function _run(cmd) {
        runProc.command = cmd;
        runProc.running = true;
    }

    function refresh(): void {
        wsProc.running = true;
        winProc.running = true;
        focusProc.running = true;
    }

    Process {
        id: wsProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text).sort((a, b) => a.idx - b.idx);
                    const sig = JSON.stringify(arr.map(w => [w.idx, w.output, w.is_active, w.is_focused, w.name]));
                    if (sig === root._wsSig)
                        return;
                    root._wsSig = sig;
                    root._wsRaw = arr;
                    root._model = root._build();
                } catch (e) {}
            }
        }
    }
    Process {
        id: winProc
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    // structural only (ignore titles) so title churn doesn't rebuild workspaces
                    const sig = JSON.stringify(arr.map(w => [w.id, w.workspace_id, w.app_id]).sort());
                    if (sig === root._winSig)
                        return;
                    root._winSig = sig;
                    root._winRaw = arr;
                    root._model = root._build();
                } catch (e) {}
            }
        }
    }
    Process {
        id: focusProc
        command: ["niri", "msg", "-j", "focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    const sig = w ? JSON.stringify([w.id, w.app_id, w.title]) : "null";
                    if (sig === root._focSig)
                        return;
                    root._focSig = sig;
                    root._focused = w;
                } catch (e) {
                    if (root._focSig !== "null") {
                        root._focSig = "null";
                        root._focused = null;
                    }
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

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {}

        function listSpecialWorkspaces(): string {
            return "";
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: false
    }
}
