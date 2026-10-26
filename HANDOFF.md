# Handoff: niri rice + dotfiles repo

For the next AI agent. Read this first, then `README.md`. Owner: user "nyx" (git author `nyx <mitch@mitch.pro>`), Arch Linux, host
`hephaestus`, linux-hardened, niri 26.04, 1920x1080 laptop. Goal they gave: "rice the hell out of niri, make no mistakes".

## Ground rules (from the user, keep following them)
- The `~/dotfiles` git repo is **local only, no remote**. Never add one or push. Commits end with
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and use `git -c user.name=nyx -c user.email=mitch@mitch.pro` (no global identity is set).
- `~/AGENTS.md`: the "run `notify-me` when done" and "commit and push to master" rules apply **only** to repos under github.com/mitch-pro/mitch.pro. Not here.
- `~/.config/rice/.env` holds ntfy credentials. chmod 600, never tracked, never print it. `notify-me` parses it without executing it.
- No password prompts for VPN / network-privacy actions: polkit policy `org.rice.net` is `allow_active=yes` (disclosed to the user).
- Do not bypass the PIA daemon's client authorization (`/opt/piavpn/var/daemon.sock` only accepts PIA binaries).
- Hostname spoofing may only affect what Wi-Fi sees (iwd private hostname via a systemd `ProtectHostname=private:` drop-in), never the system hostname.
- Boot loader work: be careful, keep a rollback, never change boot order unless every check passed.
- Ask before changing the user's theme/system state for a test. Past mistakes: flipping system light/dark during tests, running `theme-mode dark` because a state file said dark, overwriting the real SDDM background from a fake-HOME test. Restore anything you touch.
- The auto-mode classifier sometimes returns "no verdict": retry once, do other work meanwhile. A security-weakening change was blocked once (LibreWolf signature check) and only done after explicit approval. Do not route around a denial.

## Shell gotchas
- Never `pkill -f <pattern>` where the pattern is in your own command line (killed the shell several times). Use `pkill -x name` or kill by PID from `ps ... | grep '[x]yz'`.
- zsh: `echo =====` fails; `ls` is aliased to eza (use `command ls`). `cat` is NOT aliased (removed on purpose).
- Files written through tool calls turn literal `\uXXXX` into real glyphs; match real characters when editing existing QML (python `""`).
- QML pitfalls hit so far: reserved/clashing names (`super`, `State`, props starting `on`+capital, an Item property named `left`). Check errors with `quickshell -c bar log` (the bar reloads itself on file save).
- niri session PATH lacks `~/.local/bin`, so binds/startup entries use absolute `/home/nyx/...` paths.

## Repo layout (`~/dotfiles`)
| path | what |
|---|---|
| `install.sh` | one-shot installer (see below) |
| `deps.sh` | root part: packages (+AUR PIA via yay), net helper + polkit, logind drop-in, SilentSDDM, services, shell. Idempotent. `SKIP_GRUB=1`, `SKIP_BOOT_THEME=1` skip boot steps |
| `sync.sh` | live `$HOME` -> repo: configs, scripts, wallpapers (not `*.ai`), `assets/`, `root/etc/sddm.conf`. Run before every commit |
| `home/` | dotfiles + `~/.local/bin` scripts + LibreWolf extension source |
| `wallpapers/` | the user's wallpapers (31 MB), `assets/Nordic-darker.tar.xz` |
| `root/` | root-owned files: `usr/local/lib/rice/net-helper`, polkit policy, sddm.conf |
| `boot/` | `boot-theme.sh` (plymouth / grub / splash / preview), `switch-to-grub.sh` |
| `README.md`, `change-username.txt` | usage, username-rename steps |

Workflow: edit live files in `~/.config`, `~/.local/bin` -> `./sync.sh` -> commit. Copies of the boot scripts also live at `~/boot-theme.sh` and `~/deps.sh` (copy after editing the repo version; sync copies `~/deps.sh` into the repo).

`install.sh [--no-root] [--no-boot] [--no-wallpapers]`: sudo `deps.sh` (boot steps skipped) -> copy `home/` (backups to `~/.config-backup-*`, rewrites `/home/nyx` to `$HOME`) -> wallpapers -> Nordic-darker, powerlevel10k clone -> LibreWolf profile files + xpi build + matugen path fix -> first colours via `theme-mode` -> pipewire, nvim plugins -> sudo boot steps. The user part was tested in a fake HOME with stubs; the root part and boot steps were **never run end to end by me**.

## The desktop
- **niri** `~/.config/niri/config.kdl` + generated `colors.kdl` (matugen). Startup: awww-daemon (+ `--namespace backdrop` for the overview), wallpaper restore, `quickshell -c bar`, xwayland-satellite, polkit-gnome, swayidle (lock/timeouts call `~/.local/bin/lock`), cliphist watchers, `clip-prune --daemon`, `vpn-autoconnect`.
  Notable binds: `Ctrl+\`` / `Ctrl+Shift+\`` wallpaper next/prev, `Mod+Shift+W` picker, `Mod+Space`/`Mod+D` launcher, `Alt+Tab` switcher, `Mod+A` quick settings, `Mod+N` notifications, `Mod+X` power menu, `Mod+Shift+T` light/dark, `Mod+Y` clipboard, `Mod+Shift+S` screenshot, ``Mod+` `` scratch terminal, `Mod+Alt+T` timer/todo, `Super+Alt+L` lock, `Mod+Up/Down` workspace, `Mod+Shift+Up/Down` and `Mod+Shift+1..9` move window to workspace.
- **matugen** `~/.config/matugen/config.toml` + `templates/`: outputs for kitty, niri, fuzzel, swaylock, GTK3/4, quickshell `bar/colors.json`, btop, sddm (`~/.cache/rice/sddm.conf`), nvim `palette.lua`, LibreWolf `chrome/colors.css`.
- **Scripts** (`~/.local/bin`): `wallpaper` (next|prev|random|restore|set|mode), `theme-mode [dark|light|toggle] [--no-restore]`, `lock`, `lid-close`, `rec`, `shot`, `clip`, `clip-prune`, `scratch`, `notify-me`, `caffeine-off`, `vpn-autoconnect`, `boot-preview`, `librewolf-theme-host`.
- **Light/dark**: mode in `~/.cache/rice/mode`; `theme-mode` sets gsettings + GTK theme (dark = Nordic-darker, light = Adwaita) then `wallpaper restore`. Per-wallpaper preference in `~/.config/rice/wallpaper-modes.json` (keyed by file name; set with `m` or the badge in the picker, or `wallpaper mode <file> light|dark|auto`); it applies on next/prev/random/set, NOT on restore (`WALLPAPER_KEEP_MODE=1`), so a manual toggle sticks.
- **Quickshell bar** `~/.config/quickshell/bar` (every component must be listed in `qmldir`). Singletons: Theme, Niri, UiState, Wifi (iwd), Vpn (PIA piactl monitors), NetStats, Weather (Open-Meteo), Captive, Automation (per-SSID rules), Caffeine, Power, Focus (timer/todo). Components: Bar, DynamicIsland (+Events, Island/Glyph/Label/Controls), Workspaces, Stats (CPU/RAM/temp only now; network lives in Monitor), Monitor, QuickSettings (pages: main, wifi, bluetooth, audio, vpn, weather, caffeine, power, privacy), History, MediaPopup, Launcher, Switcher, TrayMenu, PowerMenu, WallpaperPicker, Notifications (built-in daemon), FocusPanel.
  Bar layout now: left = launcher, workspaces, weather chip (hides/shrinks the title to avoid the island), window title; right = media, stats, tray, icon cluster (recording timer, caffeine, VPN, Wi-Fi, volume (hidden at 0% or muted), battery % (hidden at 100), bell, power). The wallpaper button and calendar were removed on purpose.
  IPC targets: `quickshell -c bar ipc call <power|wallpaper|quick|history|media|dnd|caffeine|launcher|switcher|monitor|focus> ...`.
- **Lock screen** `~/.config/quickshell/lock` (symlinks Theme/Wifi/Vpn/Weather/colors.json from bar; `LOCK_TEST=1` auto-unlocks after 6 s, `LOCK_PREVIEW=1` window mode); swaylock fallback if it does not engage in 4 s.
- **Caffeine / super caffeine**: stop timer, battery cutoff, lid behaviour, idle/screen-off minutes; super holds `systemd-inhibit`. Island text for super is just "Super caffeine".
- **Clipboard**: cliphist; `clip-prune` deletes entries older than 60 min (state in `~/.cache/rice/clip-seen`, `CLIP_MAX_MIN` to change, `--wipe`). Deleted values may linger in free pages of the bbolt db (offered, not done: rebuild the db).
- **VPN (PIA)**: all through `piactl`; TCP 443 pinning, killswitch and region via the root helper. `vpn-autoconnect` runs once per login (flag in `$XDG_RUNTIME_DIR`), setting in `~/.config/rice/vpn.json`, toggle on the VPN page ("Connect at startup"). Killswitch is currently "Always on". `piactl` cannot set transport/port.
- **Root helper** `/usr/local/lib/rice/net-helper` (source in `root/`): status, mode, range, always, rotate, rule(s), hostname, dhcp-hostname, boot-hostname, harden, pia, pia-killswitch, sync. MAC randomization mode `network`; per-network rules in `/var/lib/rice-net/state.json`.
- **Neovim** `~/.config/nvim` (lazy.nvim; `lua/palette.lua` rewritten by matugen and applied live via fs_event). **Kitty** cursor trail, splits layout. Final nvim UI was never screenshotted.
- **Lid close**: `lid-close` suspends itself if logind did not (logind `HoldoffTimeoutSec=3s` drop-in); skips when docked/super.

## LibreWolf (live colours)
- Profile `~/.config/librewolf/librewolf/6yv4qbnb.default-release` (name differs per machine; install.sh handles it and rewrites the matugen output path).
- `chrome/userChrome.css` takes colours from the **browser theme** (`--rice-*` aliases of `--toolbar-background-color`, `--panel-background-color`, `--tab-background-color-selected`, ... names for Firefox 158; the old `--toolbar-bgcolor` names no longer work). The tiny extension **rice theme** (`home/.local/share/rice/librewolf-ext`, installed as `<profile>/extensions/rice-theme@local.xpi`) gets colours from the native host `~/.local/bin/librewolf-theme-host` (watches `~/.config/quickshell/bar/colors.json`, logs to `~/.cache/rice/lw-theme-host.log`; manifest `~/.librewolf/native-messaging-hosts/rice_theme.json`) and calls `browser.theme.update`. Result: wallpaper and light/dark changes recolour open windows live.
- Requires `xpinstall.signatures.required=false` and `extensions.autoDisableScopes=0` in `user.js` (user approved; unsigned extension). The very first start after installing did not start the host once; later starts did. `userContent.css` (new tab / about pages) still uses the static `colors.css`.
- Old single-palette `userChrome.css` backup: `~/.cache/rice/userChrome.before.css`.

## Boot (GRUB 2.16 starting UKIs; UEFI, Secure Boot off, LUKS root with `encrypt` hook)
- The machine boots **GRUB** (not systemd-boot: stale NVRAM entries misled an early diagnosis). UKIs live in `/boot/EFI/Linux`; `/boot` is root-only so non-root agents cannot read `grub.cfg`.
- `boot/boot-theme.sh` (needs sudo except `status --dry-run`, `grub --dry-run`, `preview`): `plymouth` builds an EXTRA image `arch-linux-hardened-splash.efi` (hook `plymouth` after `udev`, config `/etc/mkinitcpio-splash.conf`, custom **script-module** theme `rice` in `/usr/share/plymouth/themes/rice`: wallpaper, rotating ring, "Unlock your disk" entry with one dot per character, dots shrink/squeeze up to 96 chars, shake on wrong passphrase; state is written with `global.` inside functions). `grub` writes `/boot/grub/themes/rice` (card, accent selection pill with bold text, fonts), switches off the stock generators (`15_uki`, `25_bli`, `30_os-prober`, `31_efi_bootnext`, restored by a pacman hook after grub upgrades), writes `/etc/grub.d/15_rice` (Plymouth image first = default "Arch Linux", plain image "Arch Linux (no splash)", others under "Advanced") and `99_rice` (Restart / Shut down), sets `GRUB_DISABLE_OS_PROBER=true`, and verifies `grub.cfg` contains the `chainloader` line before finishing (otherwise restores the stock entries). `splash` rebuilds the main UKI with a splash picture.
- GRUB no longer sets `LoaderInfo` (entries chainload the UKI), so detection falls back to `/etc/grub.d/15_rice` or `/boot/grub/grub.cfg`.
- `boot/switch-to-grub.sh` does nothing on this machine (already GRUB); on systemd-boot it installs GRUB beside it with backup/rollback.
- `boot-preview` opens approximate windows of the GRUB menu and Plymouth passphrase screen (`~/.config/quickshell/bootpreview`, assets in `~/.cache/rice/bootpreview`). Real rendering differs a little.
- **Unverified on real hardware**: the Plymouth theme script (written from the stock `script` theme API, never executed here), the new GRUB look, the earlier report that the old spinner froze at a third (cause unknown; new ring is timer-driven). If Plymouth misbehaves the user boots the "no splash" entry.

## Known gaps / ideas not done
- Never tested for real: lid-close/super with an actual lid, per-network automation firing, mixer sliders, caps/num/mic island OSD, real `notify-me` send, full `caffeine-off`, hostname private-name (needs systemd >= 256, unchecked), `install.sh` root part and boot steps on a clean machine, SilentSDDM clone URL (`github.com/uiriansan/SilentSDDM`, taken from the theme's own files).
- Offered, not requested: encrypted off-machine config backup, themed polkit prompt, Discord/Spotify theming (apps not installed), quieter bar log (the `recording` FileView warns when the file is missing), rebuilding the cliphist db after pruning.
- Leftover root files from the removed palm guard may remain: `/usr/local/lib/rice/palm-guard`, `/etc/systemd/system/rice-palm-guard.service` (the user was given the `sudo rm` line).
- Wallpapers named `*.ai` in `~/Pictures/Wallpapers` are old generated placeholders the user renamed to hide them; they are not in the repo.
- Renaming the user: see `change-username.txt`.

## Current state when this was written
Mode and wallpaper are whatever the user last chose (they switch often); latest commit on `~/dotfiles` master is the one containing this file. Run `git -C ~/dotfiles log --oneline | head` and `quickshell -c bar log | tail` first to see where things stand.
