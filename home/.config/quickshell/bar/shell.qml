//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    Bar {}
    Calendar {}
    QuickSettings {}
    History {}
    MediaPopup {}
    PowerMenu {}
    WallpaperPicker {}
    Notifications {}
    Events {}

    // qs -c bar ipc call <target> toggle
    IpcHandler { target: "power";     function toggle(): void { UiState.power = !UiState.power; } }
    IpcHandler { target: "calendar";  function toggle(): void { UiState.calendar = !UiState.calendar; } }
    IpcHandler { target: "wallpaper"; function toggle(): void { UiState.wallpaper = !UiState.wallpaper; } }
    IpcHandler {
        target: "quick"
        function toggle(): void { if (UiState.quick) UiState.quick = false; else UiState.openQuick("main"); }
        function open(page: string): void { UiState.openQuick(page); }
    }
    IpcHandler { target: "history";   function toggle(): void { UiState.history = !UiState.history; } }
    IpcHandler { target: "media";     function toggle(): void { UiState.media = !UiState.media; } }
    IpcHandler { target: "dnd";       function toggle(): void { UiState.dnd = !UiState.dnd; } }
    IpcHandler { target: "caffeine";  function toggle(): void { UiState.caffeine = !UiState.caffeine; } }
}
