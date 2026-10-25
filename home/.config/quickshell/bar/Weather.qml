pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Open-Meteo (no key). Location lives in ~/.config/rice/weather.json: {"name","lat","lon","unit":"f"|"c"}.
Singleton {
    id: root
    readonly property string cfg: Quickshell.env("HOME") + "/.config/rice/weather.json"

    property bool configured: false
    property string name: ""
    property real lat: 0
    property real lon: 0
    property string unit: "f"
    property bool loaded: false
    property real temp: 0
    property real feels: 0
    property int code: 0
    property bool day: true
    property real wind: 0
    property real high: 0
    property real low: 0
    property string error: ""
    property var results: []

    readonly property string icon: {
        const c = code;
        if (c === 0) return day ? "" : "";
        if (c <= 2) return day ? "" : "";
        if (c === 3) return "";
        if (c === 45 || c === 48) return "";
        if (c >= 51 && c <= 67 || c >= 80 && c <= 82) return "";
        if (c >= 71 && c <= 77 || c === 85 || c === 86) return "";
        if (c >= 95) return "";
        return "";
    }
    readonly property string desc: {
        const c = code;
        if (c === 0) return "Clear";
        if (c <= 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c === 45 || c === 48) return "Fog";
        if (c >= 51 && c <= 57) return "Drizzle";
        if (c >= 61 && c <= 67 || c >= 80 && c <= 82) return "Rain";
        if (c >= 71 && c <= 77 || c === 85 || c === 86) return "Snow";
        if (c >= 95) return "Thunderstorm";
        return "Cloudy";
    }
    readonly property color color: code === 0 ? (day ? Theme.yellow : Theme.blue) : code >= 95 ? Theme.magenta : code >= 51 ? Theme.cyan : Theme.textDim
    readonly property string tempText: Math.round(temp) + "°" + unit.toUpperCase()

    function refresh() { if (configured) fetch.running = true; }
    function search(q) {
        if (!q) return;
        geoQuery = q;
        geo.running = true;
    }
    property string geoQuery: ""
    function choose(r) {
        const j = JSON.stringify({ name: r.name + (r.admin1 ? ", " + r.admin1 : ""), lat: r.latitude, lon: r.longitude, unit: unit });
        save.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", cfg, j];
        save.running = true;
        results = [];
    }
    function setUnit(u) {
        unit = u;
        if (configured) choose({ name: name, latitude: lat, longitude: lon, admin1: "" });
    }

    Process { id: save; onExited: file.reload() }
    FileView {
        id: file
        path: root.cfg
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: root.configured = false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.name = j.name; root.lat = j.lat; root.lon = j.lon; root.unit = j.unit || "f";
                root.configured = true;
                root.refresh();
            } catch (e) { root.configured = false; }
        }
    }
    Process {
        id: fetch
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.lat + "&longitude=" + root.lon
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
            + "&temperature_unit=" + (root.unit === "f" ? "fahrenheit" : "celsius") + "&wind_speed_unit=" + (root.unit === "f" ? "mph" : "kmh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.temp = j.current.temperature_2m; root.feels = j.current.apparent_temperature;
                    root.code = j.current.weather_code; root.day = j.current.is_day === 1; root.wind = j.current.wind_speed_10m;
                    root.high = j.daily.temperature_2m_max[0]; root.low = j.daily.temperature_2m_min[0];
                    root.loaded = true; root.error = "";
                } catch (e) { root.error = "offline"; }
            }
        }
    }
    Process {
        id: geo
        command: ["curl", "-s", "--max-time", "10", "https://geocoding-api.open-meteo.com/v1/search?count=5&language=en&format=json&name=" + encodeURIComponent(root.geoQuery)]
        stdout: StdioCollector {
            onStreamFinished: { try { root.results = JSON.parse(text).results || []; } catch (e) { root.results = []; } }
        }
    }
    Timer { interval: 1800000; running: root.configured; repeat: true; onTriggered: root.refresh() }
}
