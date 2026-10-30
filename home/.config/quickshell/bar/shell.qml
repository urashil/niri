//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    Bar {}
    QuickSettings {}
    History {}
    MediaPopup {}
    ClaudePopup {}
    ClaudeAsk {}
    PasswordDrill {}
    UsbPrompt {}
    Launcher {}
    Monitor {}
    FocusPanel {}
    Switcher {}
    PowerMenu {}
    QuitPrompt {}
    WallpaperPicker {}
    Notifications {}
    SongIsland {}
    AuthPrompt {}
    Events {}

    // qs -c bar ipc call <target> toggle
    IpcHandler {
        target: "power"
        function toggle(): void { UiState.power = !UiState.power; }
        // Mod+Shift+E: ask first; pressing it again while asked logs out
        function quit(): void { if (UiState.quitAsk) Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]); else { UiState.power = false; UiState.quitAsk = true; } }
        function cancel(): void { UiState.quitAsk = false; }
    }
    IpcHandler { target: "wallpaper"; function toggle(): void { UiState.wallpaper = !UiState.wallpaper; } }
    IpcHandler {
        target: "quick"
        function toggle(): void { if (UiState.quick) UiState.quick = false; else UiState.openQuick("main"); }
        function open(page: string): void { UiState.openQuick(page); }
    }
    IpcHandler { target: "history";   function toggle(): void { UiState.history = !UiState.history; } }
    IpcHandler { target: "drill";     function toggle(): void { UiState.drill = !UiState.drill; } }
    IpcHandler {
        target: "ask"
        function open(): void { UiState.askClaude("", ""); }
        function close(): void { UiState.ask = false; }
        function question(q: string): void { UiState.askClaude(q, ""); }
        function image(path: string): void { UiState.askClaude("", path); }
    }
    IpcHandler {
        target: "claude"
        function toggle(): void { UiState.claude = !UiState.claude; }
        // from the Claude Code hooks (claude-island)
        function event(state: string, win: string, project: string, msg: string, ping: string): void { ClaudeUsage.event(state, parseInt(win), project, msg, ping === "1"); }
        function changed(): void { ClaudeUsage.listSessions(); }
    }
    IpcHandler { target: "media";     function toggle(): void { UiState.media = !UiState.media; } }
    IpcHandler {
        target: "monitor"
        function toggle(): void { UiState.monitor = !UiState.monitor; }
        function open(tab: string): void { UiState.monitorTab = tab; UiState.monitor = true; }
    }
    IpcHandler {
        target: "focus"
        function toggle(): void { UiState.focusOpen = !UiState.focusOpen; }
        function open(tab: string): void { UiState.focusTab = tab; UiState.focusOpen = true; }
        function timer(minutes: int): void { Focus.start(minutes); }
        function pomodoro(): void { Focus.startPomodoro(); }
        function stopwatch(): void { Focus.startStopwatch(); }
        function stop(): void { Focus.stop(); }
        function todo(text: string): void { Focus.addTodo(text); }
    }
    IpcHandler {
        target: "vpn"
        function wg(): void { Vpn.useWireguard(); }
        function school(): void { Vpn.useSchool(); }
        function auto(): void { Vpn.useOpenvpnAuto(); }
    }
    // qs -c bar ipc call song <open|toggle|expand|key>   (key: play-pause|next|previous|stop, for the media keys)
    IpcHandler {
        target: "song"
        function open(): void { Song.open(); }
        function toggle(): void { Song.toggle(); }
        function expand(): void { if (Song.started) UiState.songOpen = !UiState.songOpen; else Song.open(); }
        function key(what: string): void { Song.key(what); }
        function state(): string { return JSON.stringify({ started: Song.started, playing: Song.playing, pos: Song.position, open: UiState.songOpen, film: Song.filmReady, frames: Song.frameCount }); }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { UiState.launcher = !UiState.launcher; }
        function open(text: string): void { UiState.launcherText = text; UiState.launcher = true; }
    }
    IpcHandler {
        target: "switcher"
        function next(): void { UiState.switcherStep(1); }
        function prev(): void { UiState.switcherStep(-1); }
    }
    // scripts: show a line in the island for a few seconds
    IpcHandler { target: "island"; function pulse(text: string): void { UiState.pulse("ipc", "\uf05a", text, -1, Theme.primary, 4000); } }
    IpcHandler { target: "dnd";       function toggle(): void { UiState.dnd = !UiState.dnd; } }
    IpcHandler {
        target: "caffeine"
        function toggle(): void { UiState.caffeine = !UiState.caffeine; }
        function cycle(): void { UiState.cycleCaffeine(); }
        function off(): void { UiState.superCaffeine = false; UiState.caffeine = false; }
        function superMode(): void { UiState.superCaffeine = !UiState.superCaffeine; }
        // from ~/.local/bin/awake
        function jobs(): void { Caffeine.refreshJobs(); }
        function finished(name: string, code: string, took: string): void { Caffeine.finished(name, code, took); }
        function state(): string { return JSON.stringify({ caffeine: UiState.caffeine, superCaffeine: UiState.superCaffeine, jobs: Caffeine.jobs }); }
    }
}
