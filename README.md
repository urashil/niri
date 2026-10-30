# dotfiles (local)

niri + quickshell bar, matugen colours from the wallpaper, kitty/zsh/p10k, SilentSDDM synced to the wallpaper.

## Install (Arch Linux)

```
./install.sh               # everything: packages, root helpers, configs, wallpapers, themes, GRUB/Plymouth
./install.sh --no-root     # user part only (no sudo): configs, wallpapers, themes
./install.sh --no-boot     # leave GRUB / Plymouth alone
```

It is safe to re-run; anything it replaces in `$HOME` is first saved to `~/.config-backup-<date>`. After it finishes, log out
and back in, and restart LibreWolf once.

- `install.sh`  the one entry point (calls `deps.sh` through sudo, then copies `home/`, `wallpapers/`, builds the LibreWolf extension)
- `deps.sh`     root part: packages (+ PIA from the AUR via yay), network-privacy helper + polkit rule, SilentSDDM, services
- `sync.sh`     the other direction: copy the live config, scripts and wallpapers from `$HOME` into this repo
- `home/`       dotfiles and scripts, `wallpapers/` the wallpaper set, `assets/` GTK theme archive, `root/` root-owned files, `boot/` GRUB + Plymouth scripts

Keybinds worth knowing: `Ctrl+\`` next wallpaper, `Mod+Shift+W` picker, `Mod+Space` launcher
(`w ` windows, `c ` clipboard, `> ` run, `s ` web, maths inline), `Alt+Tab` window switcher,
`Mod+A` quick settings (Wi-Fi, Bluetooth, VPN, privacy, weather), `Mod+N` notifications,\
`Super+Shift+Up/Down` and `Super+Shift+1..9` move the window between workspaces, click the island for tasks,
`Mod+X` power menu, `Mod+Y` clipboard, `Mod+Shift+S` screenshot+annotate, ``Mod+` `` scratch terminal,
`Mod+Shift+D` do not disturb, `Mod+Shift+B` caffeine, `Mod+Shift+T` light/dark, `Super+Alt+L` lock.

Each wallpaper can switch the theme to light or dark when applied: press `m` (or click the badge) on its thumbnail in the picker, or `wallpaper mode <file> light|dark|auto`.

Lock screen: `~/.local/bin/lock` runs the quickshell lock (`~/.config/quickshell/lock`) and falls back to
swaylock if it does not engage within 4 s. `LOCK_TEST=1 lock` auto-unlocks after 6 s for testing,
`LOCK_PREVIEW=1 quickshell -c lock` shows the UI in a normal window.

PIA: everything goes through `piactl`; the TCP/443 transport has to be pinned once (PIA app, or the quick
settings VPN page, no password prompt once deps.sh has installed the polkit rule) because `piactl` has no port setting.

Clipboard history keeps only the last 60 minutes (`clip-prune --daemon`, started by niri; `CLIP_MAX_MIN` changes it, `clip-prune --wipe` clears it).

LibreWolf colours follow the wallpaper live: the "rice theme" extension (`.local/share/rice/librewolf-ext`, zip it to `<profile>/extensions/rice-theme@local.xpi`) is fed by `librewolf-theme-host`; needs `xpinstall.signatures.required=false` in user.js.

Neovim: `lua/palette.lua` is rewritten by matugen and re-applied live in every running Neovim.

Agent utilities (for scripts and AI agents):
- `notify-me "message" [-t title] [-p priority] [-g tags]` sends an ntfy push using `~/.config/rice/.env`
  (`NTFY_URL`, `NTFY_PASSWORD`, optional `NTFY_USER`). `--dry-run` shows what would be sent.
- `caffeine-off [--lock]` switches caffeine / super caffeine off and turns the screen off at the same time.

Claude: the asterisk in the bar is plan usage (5 hour / weekly / all time) plus your live Claude Code sessions (click
one to jump to its terminal); the island pings when a session finishes or needs permission (hooks: `claude-island`).
`Mod+Alt+A` or `? question` in the launcher asks Claude in a card (follow-ups continue it), `Mod+Alt+S` explains a
selected part of the screen.

More: `Mod+Alt+C` colour picker (copies the hex), `Mod+Alt+P` memorize (learn a password or 50 digits in one sitting:
chunk by chunk, then reviews at 1/3/8/15/30/60 min with island nudges; Show and Remove buttons), `Mod+Y` clipboard search in the launcher (`c `), open
windows show up in the normal launcher search, night light (quick settings: sunset to sunrise at the weather location,
or always; wlsunset), per-app volume under the master slider and in Mixer (plus microphone), data used per Wi-Fi network
(Wi-Fi page), and a USBGuard prompt (bottom right) when a device gets blocked: allow once / always / later / never.

Leave it running: `awake <command>` (or `awake -p <pid>`) keeps super caffeine on until the job ends, then lets the
laptop sleep; the island says when it finished and jobs over a minute push to your phone (notify-me). Super caffeine's
"Low power while closed" switches to power saver and turns the keyboard light off while the lid is shut. Finished
downloads in ~/Downloads show in the island (click: open the folder).

Phone page: `rice-remote passwd` then `rice-remote enable` serves a read-mostly status page on 127.0.0.1:8765
(battery, temperature, super caffeine, awake jobs, Claude) with lock / screen off / let it sleep. Put it behind your
HTTPS reverse proxy; it has its own login with lockouts, strict cookies and CSP (details: `rice-remote --help`).

Chromebook keyboards: `keyboard-mode` (also run at login, and by `./install.sh --keyboard=...`) makes the **Alt** key the main
modifier (Mod) by swapping Alt and the Search key, so every `Mod+...` bind works from the Alt key; `keyboard-mode auto`
detects a Chromebook (Google DMI vendor / cros_ec keyboard), or force `keyboard-mode chromebook` / `standard`.

Timer and todo: `Mod+Alt+T`, the chips next to the clock, the launcher (`t 25`, `todo buy milk`), or
`quickshell -c bar ipc call focus timer 25` / `focus todo "text"`.

`boot-preview` opens two windows that imitate the GRUB menu and the Plymouth passphrase screen (no root).
`vpn-autoconnect on|off|status` (or quick settings > VPN > "Connect at startup") controls the VPN connecting once per login.

Boot: `sudo bash deps.sh` also applies the GRUB theme and builds the extra Plymouth entry (`SKIP_BOOT_THEME=1` skips). This machine boots GRUB 2.16, which starts the unified kernel images (UKIs) in /boot/EFI/Linux.
`boot/switch-to-grub.sh` (called by deps.sh) reads the running loader from the LoaderInfo firmware variable and
does nothing when it already says GRUB; on systemd-boot it installs GRUB beside it and only makes it first after checks.
`sudo bash boot/boot-theme.sh status` first; `preview` draws pictures of both screens without root, `grub` themes the menu and tidies its entries (one per kernel image, extras under Advanced), `splash` puts a matching picture in the kernel
image, `plymouth` builds an extra boot entry with a spinner and a themed passphrase screen (normal entry untouched).

## Song player (island)

A song that is playing stays in the center island (animated bars + what is playing). Click it and the island grows into a
player; for the `still@server` film (song.tylerium.pro) it shows the animation itself. Open it from the launcher (`still`),
`qs -c bar ipc call song open`, or the media keys (they control the film when it is loaded, otherwise `playerctl`).
`~/.local/bin/still-fetch` mirrors the song and the film's code into `~/.local/share/rice/still-at-server`
(not part of this repo); `still-film` renders it with a headless Chromium only while the island is expanded.

## Spotify

`spotify` (also what the launcher entry runs) starts spotify-launcher natively on Wayland, after (re)applying the spicetify patch when
the theme files changed or spotify-launcher replaced the client. The theme follows the wallpaper **live**, including light/dark:
matugen writes `~/.cache/rice/spotify-colors.css` (template `spotify-live.css`), the `wallpaper` script runs `spotify-theme` to put
it into Spotify's `xpui` folder, and the `rice-live` spicetify extension re-reads it every ~1.5 s. `user.css` of the `rice` theme
overrides Spotify's encore colour sets and the fixed-colour spots (page header washes, browse tiles, lyrics card) with palette roles.
`spicetify-fetch` installs spicetify itself (checksum-verified release). A spotify-launcher update replaces the patched client;
the next `spotify` start re-applies it (if you use SpotX, run it again before that).
