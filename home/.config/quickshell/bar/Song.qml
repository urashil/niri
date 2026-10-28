pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtMultimedia

// The "still@server" song (mirrored from song.tylerium.pro into ~/.local/share/rice/still-at-server) and what the island shows:
// audio is played here, the film is drawn by a headless Chromium (~/.local/bin/still-film) for the song time we send it,
// and only while the island is expanded.
Singleton {
    id: root
    readonly property string dir: Quickshell.env("HOME") + "/.local/share/rice/still-at-server"
    readonly property string name: "still@server"

    // ---- the song ----
    property var chapters: []
    property real duration: 328.032
    property real position: 0                       // seconds
    property real volume: 0.8
    property bool muted: false
    property bool started: false                    // loaded in the player (playing or paused)
    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState
    readonly property bool installed: chapters.length > 0
    readonly property int chapter: chapterAt(position)
    readonly property string chapterTitle: chapters.length > 0 ? chapters[chapter].title : ""

    function chapterAt(t) {
        let n = 0;
        for (let i = 0; i < chapters.length; i++) if (chapters[i].start <= t) n = i;
        return n;
    }
    function clock(t) { t = Math.max(0, Math.floor(t)); return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0"); }

    function play() {
        if (!installed) return;
        if (media.source.toString() === "") media.source = "file://" + dir + "/assets/still-at-server.mp3";
        if (media.mediaStatus === MediaPlayer.EndOfMedia) media.position = 0;
        started = true;
        media.play();
    }
    function pause() { media.pause(); }
    function toggle() { if (playing) pause(); else play(); }
    function stop() { media.stop(); started = false; position = 0; UiState.songOpen = false; }
    function seek(t) { t = Math.max(0, Math.min(duration - 0.5, t)); media.position = t * 1000; anchorPos = t; anchorStamp = Date.now(); position = t; sendClock(); }
    function nextChapter() { if (chapter + 1 < chapters.length) seek(chapters[chapter + 1].start); }
    function prevChapter() { seek(position - chapters[chapter].start > 3 || chapter === 0 ? chapters[chapter].start : chapters[chapter - 1].start); }
    function open() { play(); UiState.songOpen = true; }

    FileView {
        path: root.dir + "/chapters.json"
        onLoaded: { try { root.chapters = JSON.parse(text()); } catch (e) {} }
    }

    MediaPlayer {
        id: media
        audioOutput: AudioOutput { volume: root.volume; muted: root.muted }
        onPositionChanged: { root.anchorPos = position / 1000; root.anchorStamp = Date.now(); }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) { root.started = false; root.position = 0; }
        onDurationChanged: if (duration > 0) root.duration = duration / 1000
        onErrorOccurred: (e, msg) => console.warn("Song:", msg)
    }

    // the player reports its position a few times a second; in between we extrapolate so the film does not stutter
    // the renderer died while the island is open (it can when Chromium is slow to start): start it again
    Timer { id: retry; interval: 2000; onTriggered: if (root.filmWanted) film.running = true }

    property real anchorPos: 0
    property real anchorStamp: 0
    function livePosition() {
        if (!playing) return media.position / 1000;
        return Math.min(duration, anchorPos + (Date.now() - anchorStamp) / 1000);
    }
    Timer {
        interval: 250
        running: root.started
        repeat: true
        onTriggered: root.position = root.livePosition()
    }

    // ---- the film (only while the island is expanded) ----
    property int frameSlot: 0
    property int frameCount: 0
    property bool filmReady: false
    readonly property string frameBase: Quickshell.env("XDG_RUNTIME_DIR") + "/still-frame-"
    readonly property string frameUrl: frameCount > 0 ? "file://" + frameBase + frameSlot + ".jpg" : ""
    readonly property bool filmWanted: UiState.songOpen && started

    onFilmWantedChanged: { if (filmWanted) { idle.stop(); film.running = true; } else idle.restart(); }
    // keep the renderer warm for a while after collapsing, so reopening is instant
    Timer { id: idle; interval: 25000; onTriggered: { film.running = false; root.filmReady = false; root.frameCount = 0; } }

    Process {
        id: film
        command: [Quickshell.env("HOME") + "/.local/bin/still-film"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") { root.filmReady = true; return; }
                const f = line.split("\t");
                if (f[0].startsWith("frame")) { root.frameSlot = parseInt(f[1]); root.frameCount = parseInt(f[0].split(" ")[1]); }
            }
        }
        stderr: SplitParser { onRead: line => console.warn("still-film:", line) }
        onExited: { root.filmReady = false; root.frameCount = 0; if (root.filmWanted) retry.restart(); }
    }
    // the film keeps time by itself; this just re-aligns it now and then, and on seek / play / pause
    function sendClock() {
        if (!film.running || !filmReady) return;
        film.write("t " + (livePosition() + (playing ? 0.08 : 0)).toFixed(3) + " " + (playing ? "1" : "0") + "\n");
    }
    onPlayingChanged: sendClock()
    onFilmReadyChanged: sendClock()
    Timer { interval: 1000; running: root.filmWanted && root.filmReady; repeat: true; onTriggered: root.sendClock() }

    // ---- what the island shows: this song, or whatever MPRIS player is playing ----
    readonly property var mprisPlayer: {
        const l = Mpris.players.values;
        for (let i = 0; i < l.length; i++) if (l[i].isPlaying) return l[i];
        return null;
    }
    readonly property string artUrl: !playing && mprisPlayer && mprisPlayer.trackArtUrl ? mprisPlayer.trackArtUrl : ""
    readonly property bool nowPlaying: playing || mprisPlayer !== null
    // what the island says: the song and the scene it is in, or "artist – title" for another player
    readonly property string nowText: playing ? name + (chapterTitle ? " · " + chapterTitle : "")
        : mprisPlayer ? (mprisPlayer.trackArtist ? mprisPlayer.trackArtist + " – " : "") + mprisPlayer.trackTitle : ""

    // media keys: this song when it is the one loaded, otherwise whatever playerctl controls
    function key(what) {
        if (playing || (started && mprisPlayer === null)) {
            if (what === "play-pause") toggle();
            else if (what === "next") nextChapter();
            else if (what === "previous") prevChapter();
            else if (what === "stop") stop();
        } else Quickshell.execDetached(["playerctl", what]);
    }
}
