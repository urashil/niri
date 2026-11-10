# Rice features

A niri + quickshell desktop. The shell is one quickshell config (`vbar`, launched as
`quickshell -c vbar`) that draws a vertical bar on the left edge plus every popout, the
dynamic island, the launcher and the lock integrations. This file documents the
non-obvious features; keybindings and file locations are at the bottom.

Most per-feature state lives under `~/.config/rice/` (settings), `~/.local/state/rice/`
(usage data) and `~/.cache/rice/` (runtime flags). Helper scripts live in `~/.local/bin/`.

---

## The bar

A 52px vertical strip on the left: launcher glyph, niri workspaces, weather, and a bottom
cluster (tray, recording timer, caffeine, Claude, mitch.pro, VPN, Wi-Fi, volume, battery,
notifications, clock, power).

Every glyph opens its popout **on hover** and closes it on a short debounce once you leave
both the glyph and the popout; a click toggles it and pins it open (click-opened popouts
ignore the hover-close). Popouts open flush against the bar, vertically centred on the
glyph that opened them.

## Dynamic island (top-centre pulldown)

Events (volume, brightness, media, battery, toggles, downloads, Claude/CI pings, etc.)
surface as a small pill at the top centre. Hover the top edge and it drops a card you
**cycle through** with the scroll wheel, the ‹ › arrows, or the page dots:

- **Time** — large clock + date.
- **Media** — art, title/artist, transport controls (MPRIS).
- **System** — CPU, memory (used / total), disk, temperature, **live network
  down/up throughput**, uptime and load average.

## Launcher ("rofi")

`Mod+Space`. Sits at the **bottom-left**: search field pinned to the bottom, results stack
**upward** with the best match nearest the input. Ranks apps, shell actions and open
windows by match quality and by how often you pick them (`~/.local/state/rice/launcher.json`,
two-week half-life). Inline maths and unit conversions evaluate as you type
(`2^10`, `5 km in mi`, `sqrt(2)`, `20 C in f`).

Typed input with no prefix just **runs as a shell command**. Prefixes:

| Prefix | Mode |
|---|---|
| `w ` | focus a window |
| `c ` | clipboard history (cliphist) |
| `e ` | emoji (copies) |
| `f ` | files (fd) |
| `> ` | run a shell command |
| `s ` | web search (DuckDuckGo) |
| `? ` | ask Claude |
| `t ` | start a timer / pomodoro / stopwatch |
| `todo ` | add a todo |

### Launcher shortcuts

Add named shortcuts in `~/.config/rice/launcher-shortcuts.json` (hot-reloaded). Type the
name to run it:

```json
[
  { "name": "school", "run": "anonium school --no-tor", "sub": "no-tor session", "icon": "network-vpn" }
]
```

`run` goes through `sh -c` (flags and args allowed). Add `"term": true` to open it in kitty.

## Claude integration

The Claude glyph opens a usage card:

- **5-hour and weekly limits** with reset countdowns (via `~/.local/bin/claude-usage`), plus
  all-time token totals read from local transcripts.
- **Multiple accounts** (`claude-account`): each account's limits are listed; click one to
  switch, and it can switch automatically when the active account hits a limit.
- **Live Claude Code sessions** reported by the Claude Code hooks — project, state
  (working / needs-you / done), and a click jumps to that terminal window.

Related:
- **Ask Claude** (`Mod+Alt+A`, or `? ` in the launcher) — answers in a card, follow-ups keep
  the conversation.
- **Explain a screen region** (`Mod+Alt+S`) — select a region and Claude explains it.
- Session state changes (a session needs you, finishes, etc.) pulse in the dynamic island.

## GitHub / mitch.pro integration

The mitch.pro glyph tracks `github.com/mitch-pro/mitch.pro` (via `~/.local/bin/mitch-gh`,
read-only polling):

- **Deployments waiting on your approval** — approve inline (the only write it makes).
- **Recent failed workflow runs** (CI, deploy, notify, …) — click to open, ✕ to dismiss one
  from the card (GitHub keeps it in the recent list otherwise).
- **Open pull requests** with author, age and review state.

New PRs and failed runs/deploys also pulse in the dynamic island.

## Wi-Fi (iwd)

Wi-Fi runs on **iwd** (not NetworkManager). The Wi-Fi popout scans, connects, and for saved
networks (right-click) sets a per-network **MAC policy** (random / stable) and what happens
on connect (see Automation). Read-only calls need no privileges.

- **Captive portals** are detected (Mozilla connectivity check, no Google) and the popout
  offers an "Open login page" button.
- **Data usage** per network is tracked by day (`~/.local/state/rice/data-usage.json`) and
  shown as today / this month / total.

## Privacy

Driven by a root helper `/usr/local/lib/rice/net-helper` invoked through `pkexec`. The
Privacy tile exposes:

- **MAC randomization** — disabled / per-connection / per-network, with a range and the
  ability to pin a custom or the permanent MAC per SSID.
- **Hostname randomization** — including a fresh hostname at boot.
- **DHCP DUID rotation** — new DUID now, or a new one every start (stops DHCP-based
  fingerprinting across sessions).
- **Hardening** toggle.

The MAC only shows after iwd reconnects, so the UI keeps polling for a few seconds after a
change.

## VPN (PIA, Mullvad or IVPN)

One VPN popout for whichever client is installed: **PIA** (`piactl`), **Mullvad** (`mullvad`) or **IVPN** (`ivpn`).
With more than one installed, a **Provider** row switches between them; switching disconnects the old one, stops and
disables its daemon and enables the new one (`net-helper vpn-daemon`), so only one client owns the firewall and DNS.
Everything goes through `~/.local/bin/vpnctl` (`vpnctl help`); the choice is kept in `~/.config/rice/vpn.json`.

State is live: `piactl monitor` and `mullvad status listen` push changes; IVPN has no event stream, so it is polled.

- **Protocol**: WireGuard / the restrictive-network transport / a fallback. PIA and IVPN: OpenVPN over TCP 443.
  Mullvad has no OpenVPN, so it uses WireGuard over TCP 443 (udp2tcp) and "Auto obfuscation" as the fallback.
  IVPN also has **WireGuard · V2Ray TCP 443** (WireGuard inside V2Ray VMESS/TCP, which looks like ordinary TCP on 443).

### IVPN menu

With IVPN as the provider the popout becomes a full IVPN menu (`IvpnMenu.qml`, data in `services/Ivpn.qml`):

- **Status card**: server (Multi-Hop entry → exit), protocol + port, uptime, tunnel/server IP, DNS, unhealthy-tunnel
  warning; connect / disconnect, **pause** (5 m – 1 day) / resume, reconnect. Plan and days left under it.
- **Server**: fastest, any of ~58 cities or a whole country, search, **ping all**, sort by ping; **Multi-Hop** with
  entry and exit picked from the same list.
- **Protocol**: WireGuard, V2Ray TCP (443), V2Ray QUIC (UDP 443), OpenVPN TCP (443) / UDP, OpenVPN obfs4; port presets;
  IPv6 in the tunnel and MTU for WireGuard.
- **Kill switch & firewall**: always on (persistent) / with VPN / off, allow LAN, allow IVPN servers, IP exceptions.
- **DNS & AntiTracker**: off / on / hardcore, block list, custom DNS with optional DoH.
- **Split tunnel**: on/off, inverse mode, launch a command inside it, running apps.
- **Trusted Wi-Fi**: IVPN's own trusted/untrusted rules for the current network and the actions they trigger.
- **Advanced**: connect when the IVPN service starts, WireGuard key rotation, new keys.

Connection options (protocol, port, server, Multi-Hop, IPv6, MTU) are `ivpn connect` flags, so `vpnctl ivpn-set` keeps
them in `~/.config/rice/vpn.json` and reconnects when the tunnel is up; the rest are IVPN daemon settings.
- **Kill switch** (on / auto / off): cuts traffic until the VPN connects. Mullvad maps "on" to lockdown mode and has
  no "off" (it always blocks an unexpected drop). IVPN "on" is the persistent (always-on) firewall.
- **Region**: PIA regions, Mullvad countries and cities, IVPN countries ("Auto" = PIA's choice, any Mullvad relay,
  IVPN's fastest server).

## Per-network automation

`~/.config/rice/networks.json` holds rules applied **when you connect** to an SSID:

- **VPN**: WireGuard / restrictive-network transport (TCP 443) / off.
- **Kill switch**: on / auto / off.
- **Quiet** (do-not-disturb) on connect.
- **Sign in first**: drops VPN + kill switch, runs `~/.config/rice/network-login.sh` for the
  captive portal, then restores the VPN and kill-switch settings.

## Phone access (rice-remote)

`~/.local/bin/rice-remote` serves a phone page over an SSH tunnel (HTTPS), as two user
services (page server + tunnel) with their own switches. Uses **passkeys**; failed sign-ins
and actions taken from the phone show in the island.

## Caffeine / super caffeine

- **Caffeine** — a Wayland idle inhibitor: screen stays on, no idle lock.
- **Super caffeine** — also blocks logind suspend / lid-switch (via `systemd-inhibit`), with
  options for lid behaviour, idle lock / screen-off after N minutes, blocking manual suspend,
  and low-power while the lid is closed. Turning it off reaps any orphaned inhibitor left by
  a previous shell session, so a stale process can't keep the laptop awake.
- Optional **stop-after** timer and **battery cutoff** (turn off below N% while discharging).
- `~/.local/bin/awake <command>` keeps super caffeine on while a job runs and turns it back
  off when the last job finishes (also pushes a notification for jobs over a minute).

## Other features

- **Night light** — `wlsunset`: off / auto (sunset→sunrise at the weather location) / on,
  with a warmth slider.
- **Weather** — Open-Meteo (no key); location in `~/.config/rice/weather.json`.
- **Power profiles** — automatic on plug/unplug/battery threshold; a profile picked by hand
  sticks until the next change.
- **Focus** — countdown / pomodoro / stopwatch timer and a todo list, both shown in the
  island; timer survives a shell restart.
- **Memorize** (`Mod+Alt+P`) — learn a long password or number in chunks, then recall it at
  spaced intervals (~9 min) until memorized; detects and supports diceware passphrases.
  Typing is hidden; saved mode-only in `~/.local/share/rice/memorize.json` (0600).
- **Screen recording** (`Mod+Alt+R`), **screenshot + annotate** (`Mod+Shift+S`), **colour
  picker** (`Mod+Alt+C`), **wallpaper picker** (`Mod+Shift+W`) with next/prev.
- **still@server** — an animated music "film" rendered by a headless Chromium, played in the
  expanded island.
- **Notifications** with history and DND, **system monitor** (processes / memory /
  connections), **Bluetooth**, per-app **audio mixer**, light/dark theme toggle.

---

## Keybindings

| Key | Action |
|---|---|
| `Mod+Return` | Terminal (kitty) |
| `Mod+Space` | Launcher |
| `Mod+Shift+Space` | Fallback launcher (fuzzel) |
| `Alt+Tab` | Window switcher |
| `Mod+Shift+T` | Light / dark |
| `Mod+X` | Power menu |
| `Mod+Shift+W` | Wallpaper picker |
| `Mod+A` | Quick settings |
| `Mod+N` | Notification history |
| `Mod+Shift+D` | Do not disturb |
| `Mod+Shift+B` | Caffeine / super caffeine |
| `Ctrl+Shift+Escape` | Task monitor |
| `Mod+Alt+R` / `Mod+Alt+Shift+R` | Record screen / region |
| `Mod+Alt+T` | Timer / todo |
| `Mod+Y` | Clipboard history |
| `Mod+Alt+A` | Ask Claude |
| `Mod+Alt+S` | Explain a screen region (Claude) |
| `Mod+Alt+P` | Memorize |
| `Mod+Alt+C` | Colour picker |
| `Mod+Shift+S` | Screenshot + annotate |
| `Mod+Grave` | Scratch terminal |
| `Ctrl+Grave` / `Ctrl+Shift+Grave` | Next / previous wallpaper |
| `Super+Alt+L` | Lock |
| `Mod+Shift+E` | Log out |

## File locations

- **Settings** — `~/.config/rice/`: `caffeine.json`, `networks.json`, `nightlight.json`,
  `weather.json`, `power.json`, `todo.json`, `launcher-shortcuts.json`, `network-login.sh`,
  `wallpaper-modes.json`.
- **Usage data** — `~/.local/state/rice/`: `launcher.json` (pick counts),
  `data-usage.json` (per-network traffic).
- **Shared data** — `~/.local/share/rice/`: `emoji.tsv`, `memorize.json`, `still-at-server/`.
- **Runtime flags** — `~/.cache/rice/`: `timer.json`, `mode`, `super`, `super-lid`,
  `super-lowpower`, `recording`.
- **Root helper** — `/usr/local/lib/rice/net-helper` (invoked via `pkexec` for privacy/MAC).
- **Scripts** — `~/.local/bin/`: `claude-usage`, `mitch-gh`, `rice-remote`, `awake`,
  `lock`, `rec`, `shot`, `colorpick`, `explain-shot`, `theme-mode`, `wallpaper`, `scratch`,
  `still-film`, `notify-me`, `keyboard-mode`, `vpn-autoconnect`, and more.
