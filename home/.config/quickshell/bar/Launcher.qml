import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Mod+Space. Apps, actions (lock, screenshot, larp mode, dark mode, VPN…) and open windows, ranked by match and by how often
// you pick them (~/.local/state/rice/launcher.json); empty, it shows your most used first. Prefixes: "w " windows, "c " clipboard,
// "e " emoji, "f " files, "> " run, "s " web search, "? " ask Claude, "t " timer, "todo "; maths and unit conversions evaluate inline.
PanelWindow {
    id: win
    visible: UiState.launcher
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.25)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.launcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    property string query: ""
    property var clip: []
    readonly property var results: tag(build(query))

    onVisibleChanged: {
        if (visible) { clipProc.running = true; input.text = UiState.launcherText; UiState.launcherText = ""; input.forceActiveFocus(); list.currentIndex = 0; Niri.refresh(); }
    }
    function close() { UiState.launcher = false; }
    // `launcher open <text>` while it is already up
    Connections { target: UiState; function onLauncherTextChanged() { if (win.visible && UiState.launcherText !== "") { input.text = UiState.launcherText; UiState.launcherText = ""; } } }

    Process {
        id: clipProc
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: win.clip = text.split("\n").filter(l => l.length > 0).slice(0, 60) }
    }
    property var emoji: []
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/rice/emoji.tsv"
        onLoaded: win.emoji = text().split("\n").filter(l => l.length > 0).map(l => l.split("\t"))
    }
    property var files: []
    Process {
        id: fileProc
        stdout: StdioCollector { onStreamFinished: win.files = text.split("\n").filter(l => l.length > 0) }
    }
    Timer {
        id: fileDelay
        interval: 180
        onTriggered: {
            const t = win.query.slice(2).trim();
            if (t.length < 2) { win.files = []; return; }
            fileProc.command = ["fd", "--max-results", "40", "--ignore-case", "--hidden", "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules", t, Quickshell.env("HOME")];
            fileProc.running = true;
        }
    }
    function iconFor(name) { return Quickshell.iconPath(name || "application-x-executable", "application-x-executable"); }

    function score(e, q) {
        const n = (e.name || "").toLowerCase();
        if (n === q) return 200;
        if (n.startsWith(q)) return 120;
        if (n.indexOf(" " + q) >= 0) return 90;
        if (n.indexOf(q) >= 0) return 60;
        const extra = ((e.genericName || "") + " " + (e.comment || "") + " " + (e.keywords ? e.keywords.join(" ") : "")).toLowerCase();
        if (extra.indexOf(q) >= 0) return 25;
        let i = 0;
        for (const c of n) if (c === q[i]) i++;
        return i === q.length ? 10 : 0;
    }
    readonly property var fns: ["sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "abs", "round", "floor", "ceil", "exp"]
    function calc(q) {
        let t = q.toLowerCase();
        let hasFn = false;
        for (const f of fns) if (new RegExp("\\b" + f + "\\s*\\(").test(t)) { hasFn = true; t = t.replace(new RegExp("\\b" + f + "(?=\\s*\\()", "g"), f === "ln" ? "Math.log" : f === "log" ? "Math.log10" : "Math." + f); }
        t = t.replace(/\bpi\b/g, "Math.PI").replace(/\be\b/g, "Math.E");
        const bare = t.replace(/Math\.[A-Za-z0-9]+/g, "1");
        if (!/^[0-9+\-*/().%^\s,]+$/.test(bare) || !/[0-9]/.test(bare)) return null;
        if (!hasFn && !/[+\-*/%^]/.test(bare.replace(/^-/, ""))) return null;
        try {
            const v = Function('"use strict"; return (' + t.replace(/\^/g, "**").replace(/,/g, ".") + ")")();
            return typeof v === "number" && isFinite(v) ? v : null;
        } catch (e) { return null; }
    }
    // unit -> [kind, factor to the kind's base]; temperatures are handled apart
    readonly property var units: ({
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], ft: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344],
        mg: ["mass", 0.000001], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.028349523], lb: ["mass", 0.45359237], st: ["mass", 6.35029318],
        ml: ["vol", 0.001], l: ["vol", 1], tsp: ["vol", 0.00492892], tbsp: ["vol", 0.0147868], floz: ["vol", 0.0295735], cup: ["vol", 0.236588], pt: ["vol", 0.473176], qt: ["vol", 0.946353], gal: ["vol", 3.78541],
        b: ["data", 1], kb: ["data", 1000], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        s: ["time", 1], min: ["time", 60], h: ["time", 3600], d: ["time", 86400], wk: ["time", 604800],
        "m/s": ["speed", 1], "km/h": ["speed", 0.277778], kph: ["speed", 0.277778], mph: ["speed", 0.44704], kn: ["speed", 0.514444],
        c: ["temp", 0], f: ["temp", 0], k: ["temp", 0]
    })
    function convert(q) {
        const m = q.toLowerCase().trim().match(/^(-?[0-9]*\.?[0-9]+)\s*°?\s*([a-z/]+)\s+(?:in|to|as|->)\s+°?([a-z/]+)$/);
        if (!m) return null;
        const x = parseFloat(m[1]), a = units[m[2]], b = units[m[3]];
        if (!a || !b || a[0] !== b[0]) return null;
        let v;
        if (a[0] === "temp") {
            const c = m[2] === "c" ? x : m[2] === "f" ? (x - 32) * 5 / 9 : x - 273.15;
            v = m[3] === "c" ? c : m[3] === "f" ? c * 9 / 5 + 32 : c + 273.15;
        } else v = x * a[1] / b[1];
        return { v: v, text: +v.toPrecision(8) + " " + (a[0] === "temp" ? "°" + m[3].toUpperCase() : m[3]) };
    }
    function build(q) {
        const out = [];
        const run = (cmd) => Quickshell.execDetached(cmd);
        if (q.startsWith("w ") || q === "w") {
            const f = q.slice(2).toLowerCase();
            for (const w of Niri.windows) {
                if (f && (w.title + " " + w.app_id).toLowerCase().indexOf(f) < 0) continue;
                out.push({ title: w.title || w.app_id, sub: w.app_id + (w.is_focused ? " · focused" : ""), icon: iconFor(w.app_id), go: () => run(["niri", "msg", "action", "focus-window", "--id", String(w.id)]) });
            }
            return out;
        }
        if (q.startsWith("c ") || q === "c") {
            const f = q.slice(2).toLowerCase();
            for (const l of clip) {
                const t = l.replace(/^\d+\t/, "");
                if (f && t.toLowerCase().indexOf(f) < 0) continue;
                out.push({ title: t.length > 90 ? t.slice(0, 90) + "…" : t, sub: "clipboard", icon: iconFor("edit-paste"), go: () => run(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", l]) });
            }
            return out;
        }
        if (q === "e" || q.startsWith("e ")) {
            const f = q.slice(2).trim().toLowerCase();
            if (f === "") return out;
            for (const e of emoji) {
                if (e[1].indexOf(f) < 0) continue;
                out.push({ title: e[1], sub: "emoji · Enter copies", glyph: e[0], go: () => run(["wl-copy", e[0]]) });
                if (out.length >= 40) break;
            }
            return out;
        }
        if (q === "f" || q.startsWith("f ")) {
            for (const p of files) {
                const name = p.replace(/.*\//, "").replace(/\/$/, "");
                out.push({ title: name, sub: p.replace(Quickshell.env("HOME"), "~"), icon: iconFor(p.endsWith("/") ? "folder" : "text-x-generic"), go: () => run(["xdg-open", p]) });
            }
            return out;
        }
        if (q === "t" || q.startsWith("t ")) {
            const n = parseInt(q.slice(2).trim());
            if (n > 0) out.push({ title: "Start a " + n + " minute timer", sub: "timer", icon: iconFor("alarm-clock"), go: () => Focus.start(n) });
            out.push({ title: "Pomodoro  " + Focus.workMin + " / " + Focus.breakMin, sub: "timer", icon: iconFor("alarm-clock"), go: () => Focus.startPomodoro() });
            out.push({ title: "Stopwatch", sub: "timer", icon: iconFor("chronometer"), go: () => Focus.startStopwatch() });
            if (Focus.active) {
                out.push({ title: Focus.paused ? "Resume the timer" : "Pause the timer", sub: Focus.clockText, icon: iconFor("media-playback-pause"), go: () => Focus.toggle() });
                out.push({ title: "Stop the timer", sub: Focus.clockText, icon: iconFor("media-playback-stop"), go: () => Focus.stop() });
            }
            return out;
        }
        if (q.startsWith("todo ") || q.startsWith("td ")) {
            const t = q.replace(/^(todo|td)\s+/, "").trim();
            if (t) out.push({ title: "Add todo:  " + t, sub: Focus.openCount + " open", icon: iconFor("task-new"), go: () => Focus.addTodo(t) });
            return out;
        }
        if (q.startsWith(">")) {
            const c = q.slice(1).trim();
            if (c) out.push({ title: "Run  " + c, sub: "shell", icon: iconFor("utilities-terminal"), go: () => run(["sh", "-c", c]) });
            return out;
        }
        if (q.startsWith("?")) {
            const t = q.slice(1).trim();
            out.push({ title: t ? "Ask Claude:  " + t : "Ask Claude…", sub: "answers in a card · follow-ups keep the conversation", icon: iconFor("help-about"), go: () => UiState.askClaude(t, "") });
            out.push({ title: "Explain a part of the screen", sub: "select a region, Claude explains it · Mod+Alt+S", icon: iconFor("applets-screenshooter"), go: () => run([Quickshell.env("HOME") + "/.local/bin/explain-shot"]) });
            return out;
        }
        if (q.startsWith("s ")) {
            const t = q.slice(2).trim();
            if (t) out.push({ title: "Search the web for “" + t + "”", sub: "DuckDuckGo", icon: iconFor("web-browser"), go: () => run(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(t)]) });
            return out;
        }
        const v = calc(q);
        if (v !== null) out.push({ title: "= " + (Number.isInteger(v) ? v : +v.toFixed(8)), sub: "press Enter to copy", icon: iconFor("accessories-calculator"), kind: "maths", go: () => run(["wl-copy", String(v)]) });
        const cv = convert(q);
        if (cv) out.push({ title: "= " + cv.text, sub: "press Enter to copy", icon: iconFor("accessories-calculator"), kind: "convert", go: () => run(["wl-copy", String(+cv.v.toPrecision(8))]) });
        const q2 = q.toLowerCase().trim();
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        const appRow = e => ({ title: e.name, sub: e.comment || e.genericName || "", icon: iconFor(e.icon), kind: "app", key: "app:" + e.id, go: () => e.execute() });
        const winRow = w => ({ title: w.title || w.app_id, sub: w.app_id + (w.is_focused ? " · focused" : ""), icon: iconFor(w.app_id), kind: "window", go: () => run(["niri", "msg", "action", "focus-window", "--id", String(w.id)]) });

        // nothing typed: what you use most, a few actions, then everything A to Z
        if (q2 === "") {
            const top = apps.filter(e => used("app:" + e.id) > 0).sort((a, b) => used("app:" + b.id) - used("app:" + a.id)).slice(0, 5);
            for (const e of top) out.push(Object.assign(appRow(e), { kind: "frequent" }));
            const acts = actions().filter(a => used(a.key) > 0).sort((a, b) => used(b.key) - used(a.key)).slice(0, 3);
            for (const a of acts) out.push(a);
            const seen = top.map(e => e.id);
            for (const e of apps.slice().sort((a, b) => a.name.localeCompare(b.name))) if (seen.indexOf(e.id) < 0) out.push(appRow(e));
            return out.slice(0, 60);
        }

        // everything else is ranked together: match quality, plus how often you picked it
        const ranked = [];
        for (const e of apps) { const s = score(e, q2); if (s > 0) ranked.push({ r: appRow(e), s: s + boost("app:" + e.id) }); }
        for (const a of actions()) {
            const s = a.words.some(w => w === q2) ? 150 : a.words.some(w => w.startsWith(q2)) && q2.length >= 2 ? 80 : a.title.toLowerCase().indexOf(q2) >= 0 && q2.length >= 3 ? 50 : 0;
            if (s > 0) ranked.push({ r: a, s: s + boost(a.key) });
        }
        if (q2.length >= 2) for (const w of Niri.windows)
            if ((w.title + " " + w.app_id).toLowerCase().indexOf(q2) >= 0) ranked.push({ r: winRow(w), s: 40 });
        ranked.sort((a, b) => b.s - a.s || a.r.title.localeCompare(b.r.title));
        for (const x of ranked.slice(0, 40)) out.push(x.r);
        // a question-looking query: offer Claude
        if (q2.indexOf(" ") > 0 && q2.length >= 8) out.push({ title: "Ask Claude:  " + q.trim(), sub: "or start with ?", icon: iconFor("help-about"), kind: "claude", go: () => UiState.askClaude(q.trim(), "") });
        if (out.length === 0 && q2.length >= 2) out.push({ title: "Search the web for “" + q.trim() + "”", sub: "DuckDuckGo · or start with s", icon: iconFor("web-browser"), kind: "web", go: () => run(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(q.trim())]) });
        return out;
    }

    // ---- actions: things the shell can do, found by name like apps ----
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"
    function actions() {
        const run = (cmd) => Quickshell.execDetached(cmd);
        const a = (key, words, title, sub, icon, go) => ({ key: "act:" + key, words: words, title: title, sub: sub, icon: iconFor(icon), kind: "action", go: go });
        const l = [
            a("larp", ["larp", "matrix", "cmatrix", "terminals"], "Larp mode", "a wall of terminals that rearranges itself · Ctrl+Q leaves", "utilities-terminal", () => run([bin + "larp", "start"])),
            a("lock", ["lock"], "Lock", "lock the screen", "system-lock-screen", () => run([bin + "lock"])),
            a("sleep", ["sleep", "suspend"], "Sleep", "suspend", "system-suspend", () => run(["systemctl", "suspend"])),
            a("power", ["shutdown", "shut down", "power off", "restart", "reboot", "log out", "logout"], "Power menu", "shut down, restart, log out", "system-shutdown", () => { UiState.power = true; }),
            a("shot", ["screenshot", "shot", "capture"], "Screenshot an area", "select, annotate, copy · Mod+Shift+S", "applets-screenshooter", () => run([bin + "shot", "region"])),
            a("shotfull", ["screenshot", "screen"], "Screenshot the screen", "whole screen to clipboard and file", "applets-screenshooter", () => run([bin + "shot", "screen"])),
            UiState.recording
                ? a("recstop", ["record", "recording", "stop"], "Stop recording", "save the screen recording", "media-playback-stop", () => run([bin + "rec", "stop"]))
                : a("rec", ["record", "recording", "screencast"], "Record the screen", "click the red timer in the bar to stop", "media-record", () => run([bin + "rec", "screen"])),
            a("colour", ["pick", "colour", "color", "picker", "eyedropper"], "Pick a colour", "from anywhere on screen · copies the hex", "color-select", () => run([bin + "colorpick"])),
            a("explain", ["explain", "claude"], "Explain a part of the screen", "select a region, Claude explains it · Mod+Alt+S", "help-about", () => run([bin + "explain-shot"])),
            a("memorize", ["memorize", "password", "practice", "digits"], "Memorize", "learn a password or long number in chunks", "dialog-password", () => { UiState.drill = true; }),
            a("theme", ["dark", "light", "theme", "mode"], UiState.mode === "dark" ? "Switch to light mode" : "Switch to dark mode", "every app follows", "preferences-desktop-theme", () => run([bin + "theme-mode", "toggle"])),
            a("wallpaper", ["wallpaper", "background"], "Change wallpaper", "the picker", "preferences-desktop-wallpaper", () => { UiState.wallpaper = true; }),
            a("dnd", ["quiet", "dnd", "do not disturb", "notifications"], UiState.dnd ? "Quiet mode off" : "Quiet mode on", "notifications", "notifications", () => { UiState.dnd = !UiState.dnd; }),
            a("caffeine", ["caffeine", "awake", "stay awake"], UiState.caffeine ? "Caffeine off" : "Caffeine on", "keep the screen on", "preferences-desktop-screensaver", () => { UiState.caffeine = !UiState.caffeine; }),
            a("night", ["night", "night light", "blue light", "warm"], "Night light: " + (NightLight.mode === "off" ? "turn on" : NightLight.mode === "auto" ? "always on" : "off"), "now " + NightLight.mode, "weather-clear-night", () => NightLight.cycle()),
            a("vpn", ["vpn", "pia"], Vpn.connected || Vpn.busy ? "Disconnect VPN" : "Connect VPN", Vpn.label, "network-vpn", () => Vpn.toggle()),
            a("wifi", ["wifi", "wi-fi", "wireless"], Wifi.powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on", Wifi.connected ? Wifi.ssid : "not connected", "network-wireless", () => Wifi.setPowered(!Wifi.powered)),
            a("quick", ["settings", "quick settings", "volume", "brightness", "bluetooth"], "Quick settings", "", "preferences-system", () => UiState.openQuick("main")),
            a("monitor", ["monitor", "cpu", "memory", "ram", "processes", "task manager"], "System monitor", "CPU, memory, processes", "utilities-system-monitor", () => UiState.openMonitor("cpu")),
            a("history", ["notifications", "history"], "Notifications", UiState.unread + " unread", "preferences-system-notifications", () => { UiState.history = true; }),
            a("usage", ["usage", "claude", "limits"], "Claude usage", "5 hour and weekly limits", "help-about", () => { UiState.claude = true; }),
            a("todo", ["todo", "tasks", "focus", "pomodoro", "timer"], "Focus", Focus.openCount + " open tasks · timers", "task-new", () => UiState.openFocus("todo"))
        ];
        if (Song.installed) l.push(a("song", ["still@server", "song", "film", "music"], "Play " + Song.name, "the animated music film · opens in the island", "multimedia-audio-player", () => Song.open()));
        return l;
    }

    // ---- how often things get picked (ranks results, fills the empty view) ----
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.local/state/rice/launcher.json"
        printErrors: false
        onLoaded: { try { win.usage = JSON.parse(text()); } catch (e) {} }
    }
    // picks, fading with a two week half-life
    function used(key) {
        const u = usage[key];
        return u ? u.n * Math.pow(0.5, (Date.now() - u.t) / (14 * 86400000)) : 0;
    }
    function boost(key) { return Math.min(60, used(key) * 8); }
    function remember(key) {
        if (!key) return;
        const u = Object.assign({}, usage);
        u[key] = { n: used(key) + 1, t: Date.now() };
        usage = u;
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", usageFile.path, JSON.stringify(u)];
        save.running = true;
    }
    Process { id: save }

    function accept() {
        const r = results[list.currentIndex];
        if (!r) return;
        close();
        remember(r.key);
        r.go();
    }
    // prefixes: [typed, label, tag on their rows]
    readonly property var modes: [["w", "windows", "window"], ["c", "clipboard", "clipboard"], ["e", "emoji", "emoji"], ["f", "files", "file"], [">", "run", "shell"],
                                  ["s", "web", "web"], ["?", "claude", "claude"], ["t", "timer", "timer"], ["todo", "task", "todo"]]
    readonly property var mode: {
        for (const m of modes) if (query === m[0] || query.startsWith(m[0] + " ") || ("?>".indexOf(m[0]) >= 0 && query.startsWith(m[0]))) return m;
        return null;
    }
    function tag(rows) {
        if (mode) for (const r of rows) if (!r.kind) r.kind = mode[2];
        return rows;
    }

    MouseArea { anchors.fill: parent; onClicked: win.close() }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        width: 640
        height: 74 + 34 + Math.min(results.length, 8) * 54 + (results.length > 0 ? 12 : 0) + 30
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.84)
        border.width: 1
        border.color: Theme.outlineVariant
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        Text {
            id: glyph
            anchors { left: parent.left; leftMargin: 24; top: parent.top; topMargin: 25 }
            text: ""; font.family: Theme.font; font.pixelSize: 18; color: Theme.primary
        }
        TextInput {
            id: input
            anchors { left: glyph.right; leftMargin: 14; right: parent.right; rightMargin: 24; top: parent.top; topMargin: 20 }
            height: 30
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.font; font.pixelSize: 17
            color: Theme.text
            selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
            onTextChanged: { win.query = text; if (text.startsWith("f ")) fileDelay.restart(); else if (win.files.length) win.files = []; list.currentIndex = 0; if (text.startsWith("c ") && win.clip.length === 0) clipProc.running = true; if (text === "c") clipProc.running = true; }
            function step(d) { list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + d)); }
            Keys.onEscapePressed: { if (text !== "") text = ""; else win.close(); }
            Keys.onReturnPressed: win.accept()
            Keys.onEnterPressed: win.accept()
            Keys.onDownPressed: step(1)
            Keys.onUpPressed: step(-1)
            Keys.onTabPressed: step(1)
            Keys.onBacktabPressed: step(-1)
            Keys.onPressed: e => {
                if (e.modifiers & Qt.ControlModifier && (e.key === Qt.Key_N || e.key === Qt.Key_J)) { step(1); e.accepted = true; }
                else if (e.modifiers & Qt.ControlModifier && (e.key === Qt.Key_P || e.key === Qt.Key_K)) { step(-1); e.accepted = true; }
                else if (e.key === Qt.Key_PageDown) { step(8); e.accepted = true; }
                else if (e.key === Qt.Key_PageUp) { step(-8); e.accepted = true; }
            }
            Text { visible: !input.text; text: "Search apps, actions, windows…"; font: input.font; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
        }

        // modes: click one to start typing in it; the one in use is lit
        Row {
            id: modeRow
            anchors { left: parent.left; leftMargin: 20; top: parent.top; topMargin: 64 }
            spacing: 6
            Repeater {
                model: win.modes
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: win.mode === modelData
                    height: 22; radius: 11
                    width: chipText.implicitWidth + 18
                    color: on ? Theme.primaryContainer : chipHover.hovered ? Theme.surfaceHigh : "transparent"
                    border.width: 1
                    border.color: on ? Qt.alpha(Theme.primary, 0.6) : Qt.alpha(Theme.outlineVariant, 0.8)
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        textFormat: Text.StyledText
                        text: "<b>" + chip.modelData[0] + "</b>  " + chip.modelData[1]
                        font.family: Theme.font; font.pixelSize: 10
                        color: chip.on ? Theme.fgContainer : Theme.textDim
                    }
                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { input.text = chip.on ? "" : chip.modelData[0] + ("?>".indexOf(chip.modelData[0]) >= 0 ? "" : " "); input.forceActiveFocus(); } }
                }
            }
        }

        Item {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; bottomMargin: 10 }
            height: 16
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: win.results.length === 0 ? (win.query === "" ? "" : "Nothing found") : win.results.length + (win.results.length === 1 ? " result" : " results")
                font.family: Theme.font; font.pixelSize: 10; color: Theme.outline
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "↑↓  move     Enter  open     Esc  " + (win.query === "" ? "close" : "clear") + "     5 km in mi · 2^10 · sqrt(2)"
                font.family: Theme.font; font.pixelSize: 10; color: Theme.outline
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 98; leftMargin: 12; rightMargin: 12 }
            height: Math.min(results.length, 8) * 54
            clip: true
            model: win.results
            currentIndex: 0
            highlightMoveDuration: 90
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width; height: 54; radius: 14
                color: ListView.isCurrentItem ? Theme.primaryContainer : "transparent"
                IconImage { id: ic; visible: !row.modelData.glyph; implicitSize: 30; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } source: row.modelData.icon || "" }
                Text { visible: !!row.modelData.glyph; width: 30; horizontalAlignment: Text.AlignHCenter; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: row.modelData.glyph || ""; font.pixelSize: 24 }
                Text {
                    id: kindTag
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: row.modelData.kind || ""
                    font.family: Theme.font; font.pixelSize: 10
                    color: row.ListView.isCurrentItem ? Qt.alpha(Theme.fgContainer, 0.7) : Theme.outline
                }
                Column {
                    anchors { left: ic.right; leftMargin: 14; right: kindTag.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text { width: parent.width; text: row.modelData.title; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: row.ListView.isCurrentItem ? Theme.fgContainer : Theme.text }
                    Text { width: parent.width; visible: text !== ""; text: row.modelData.sub; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10; color: row.ListView.isCurrentItem ? Qt.alpha(Theme.fgContainer, 0.75) : Theme.textDim }
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: list.currentIndex = row.index; onClicked: { list.currentIndex = row.index; win.accept(); } }
            }
        }
    }
}
