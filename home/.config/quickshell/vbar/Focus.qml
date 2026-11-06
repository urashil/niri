pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Timer (countdown / pomodoro / stopwatch) and a todo list. Both show up in the dynamic island.
// Timer state survives a bar restart (~/.cache/rice/timer.json); todos live in ~/.config/rice/todo.json.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string timerPath: home + "/.cache/rice/timer.json"
    readonly property string todoPath: home + "/.config/rice/todo.json"

    // ---------------- timer ----------------
    property string mode: ""            // "" | countdown | pomodoro | stopwatch
    property bool paused: false
    property real endsAt: 0             // ms epoch while a countdown / phase is running
    property real pausedLeft: 0         // ms left while paused
    property real startedAt: 0          // stopwatch: ms epoch it (virtually) started
    property real pausedElapsed: 0
    property real totalMs: 0
    property string phase: "work"
    property int cycles: 0
    property int workMin: 25
    property int breakMin: 5
    property real now: Date.now()

    readonly property bool active: mode !== ""
    readonly property real leftMs: mode === "stopwatch" ? 0 : paused ? pausedLeft : Math.max(0, endsAt - now)
    readonly property real elapsedMs: mode === "stopwatch" ? (paused ? pausedElapsed : Math.max(0, now - startedAt)) : 0
    readonly property real fraction: mode === "stopwatch" || totalMs <= 0 ? 0 : 1 - leftMs / totalMs
    readonly property string clockText: fmt(mode === "stopwatch" ? elapsedMs : leftMs, mode !== "stopwatch")
    readonly property bool urgent: (mode === "countdown" || mode === "pomodoro") && !paused && leftMs < 60000

    function fmt(ms, up) {
        const t = Math.max(0, up ? Math.ceil(ms / 1000) : Math.floor(ms / 1000));
        const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
        const p = (n) => String(n).padStart(2, "0");
        return h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s);
    }

    function start(min) {
        mode = "countdown"; phase = "work"; paused = false;
        totalMs = min * 60000; now = Date.now(); endsAt = now + totalMs;
        persist();
        UiState.pulse("timer", "", min + " min timer started", -1, Theme.primary, 1800);
    }
    function startPomodoro() {
        mode = "pomodoro"; phase = "work"; cycles = 0; paused = false;
        totalMs = workMin * 60000; now = Date.now(); endsAt = now + totalMs;
        persist();
        UiState.pulse("timer", "", "Pomodoro · focus " + workMin + " min", -1, Theme.red, 2200);
    }
    function startStopwatch() {
        mode = "stopwatch"; paused = false; pausedElapsed = 0;
        now = Date.now(); startedAt = now;
        persist();
    }
    function pause() {
        if (!active || paused) return;
        now = Date.now();
        if (mode === "stopwatch") pausedElapsed = now - startedAt; else pausedLeft = Math.max(0, endsAt - now);
        paused = true; persist();
    }
    function resume() {
        if (!active || !paused) return;
        now = Date.now();
        if (mode === "stopwatch") startedAt = now - pausedElapsed; else endsAt = now + pausedLeft;
        paused = false; persist();
    }
    function toggle() { if (paused) resume(); else pause(); }
    function stop() { mode = ""; paused = false; endsAt = 0; persist(); }
    function skip() { if (mode === "pomodoro") finish(); }

    function alert(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "rice", "-i", "alarm-clock", title, body]);
        Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
    }
    function finish() {
        if (mode === "countdown") {
            alert("Timer done", Math.round(totalMs / 60000) + " minutes are up");
            UiState.pulse("timer", "", "Timer done", -1, Theme.yellow, 9000);
            stop();
        } else if (mode === "pomodoro") {
            if (phase === "work") {
                cycles += 1;
                const long = cycles % 4 === 0;
                phase = "break"; totalMs = (long ? 15 : breakMin) * 60000;
                alert("Break time", "Take " + (long ? 15 : breakMin) + " minutes · " + cycles + " done");
                UiState.pulse("timer", "", "Break · " + (long ? 15 : breakMin) + " min", -1, Theme.green, 9000);
            } else {
                phase = "work"; totalMs = workMin * 60000;
                alert("Back to work", next !== "" ? "Next: " + next : "Focus for " + workMin + " minutes");
                UiState.pulse("timer", "", next !== "" ? "Focus · " + next : "Focus · " + workMin + " min", -1, Theme.red, 9000);
            }
            now = Date.now(); endsAt = now + totalMs; persist();
        }
    }

    Timer {
        interval: 500; running: root.active && !root.paused; repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.mode !== "stopwatch" && root.now >= root.endsAt) root.finish();
        }
    }

    function persist() {
        const j = JSON.stringify({ mode: mode, paused: paused, endsAt: endsAt, pausedLeft: pausedLeft, startedAt: startedAt, pausedElapsed: pausedElapsed, totalMs: totalMs, phase: phase, cycles: cycles });
        saveTimer.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", timerPath, j];
        saveTimer.running = true;
    }
    Process { id: saveTimer }
    FileView {
        id: timerFile
        path: root.timerPath
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (!j.mode) return;
                if ((j.mode === "countdown" || j.mode === "pomodoro") && !j.paused && j.endsAt < Date.now()) return;   // ran out while the bar was down
                for (const k of ["mode", "paused", "endsAt", "pausedLeft", "startedAt", "pausedElapsed", "totalMs", "phase", "cycles"]) if (k in j) root[k] = j[k];
            } catch (e) {}
        }
    }

    // ---------------- todos ----------------
    property var todos: []
    readonly property int openCount: todos.filter(t => !t.done).length
    readonly property string next: { const t = todos.find(t => !t.done); return t ? t.text : ""; }

    function saveTodos(list) {
        todos = list;
        saveTodo.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", todoPath, JSON.stringify(list)];
        saveTodo.running = true;
    }
    function addTodo(text) {
        text = (text || "").trim();
        if (!text) return;
        saveTodos(todos.concat([{ text: text, done: false }]));
    }
    function toggleTodo(i) {
        const l = todos.map((t, n) => n === i ? { text: t.text, done: !t.done } : t);
        saveTodos(l);
        if (l[i].done) UiState.pulse("todo", "", l[i].text + " · done" + (openCount > 0 ? "  ·  " + openCount + " left" : "  ·  all done"), -1, Theme.green, 2200);
    }
    function removeTodo(i) { saveTodos(todos.filter((t, n) => n !== i)); }
    function clearDone() { saveTodos(todos.filter(t => !t.done)); }
    Process { id: saveTodo }
    FileView {
        path: root.todoPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j)) root.todos = j; } catch (e) {} }
    }
}
