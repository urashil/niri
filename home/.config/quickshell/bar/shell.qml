//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    Bar {}
    QuickSettings {}
    History {}
    MediaPopup {}
    Launcher {}
    Monitor {}
    FocusPanel {}
    Switcher {}
    PowerMenu {}
    WallpaperPicker {}
    Notifications {}
    SongIsland {}
    AuthPrompt {}
    Events {}

    // qs -c bar ipc call <target> toggle
    IpcHandler { target: "power";     function toggle(): void { UiState.power = !UiState.power; } }
    IpcHandler { target: "wallpaper"; function toggle(): void { UiState.wallpaper = !UiState.wallpaper; } }
    IpcHandler {
        target: "quick"
        function toggle(): void { if (UiState.quick) UiState.quick = false; else UiState.openQuick("main"); }
        function open(page: string): void { UiState.openQuick(page); }
    }
    IpcHandler { target: "history";   function toggle(): void { UiState.history = !UiState.history; } }
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
    IpcHandler { target: "launcher";  function toggle(): void { UiState.launcher = !UiState.launcher; } }
    IpcHandler {
        target: "switcher"
        function next(): void { UiState.switcherStep(1); }
        function prev(): void { UiState.switcherStep(-1); }
    }
    IpcHandler { target: "dnd";       function toggle(): void { UiState.dnd = !UiState.dnd; } }
    IpcHandler {
        target: "caffeine"
        function toggle(): void { UiState.caffeine = !UiState.caffeine; }
        function cycle(): void { UiState.cycleCaffeine(); }
        function off(): void { UiState.superCaffeine = false; UiState.caffeine = false; }
        function superMode(): void { UiState.superCaffeine = !UiState.superCaffeine; }
    }
}
