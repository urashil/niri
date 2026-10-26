# dotfiles (local)

niri + quickshell bar, matugen colours from the wallpaper, kitty/zsh/p10k, SilentSDDM synced to the wallpaper.

- `sync.sh`    copy live config from `$HOME` into `home/`
- `install.sh` copy `home/` back onto a fresh machine
- `deps.sh`    root part: packages, network-privacy helper + polkit rule, SDDM theme permissions
- `root/`      files installed as root by `deps.sh`

Keybinds worth knowing: `Ctrl+\`` next wallpaper, `Mod+Shift+W` picker, `Mod+Space` launcher
(`w ` windows, `c ` clipboard, `> ` run, `s ` web, maths inline), `Alt+Tab` window switcher,
`Mod+A` quick settings (Wi-Fi, Bluetooth, VPN, privacy, weather), `Mod+N` notifications,\
`Super+Shift+Up/Down` and `Super+Shift+1..9` move the window between workspaces, click the island for tasks,
`Mod+X` power menu, `Mod+Y` clipboard, `Mod+Shift+S` screenshot+annotate, ``Mod+` `` scratch terminal,
`Mod+Shift+D` do not disturb, `Mod+Shift+B` caffeine, `Mod+Shift+T` light/dark, `Super+Alt+L` lock.

Lock screen: `~/.local/bin/lock` runs the quickshell lock (`~/.config/quickshell/lock`) and falls back to
swaylock if it does not engage within 4 s. `LOCK_TEST=1 lock` auto-unlocks after 6 s for testing,
`LOCK_PREVIEW=1 quickshell -c lock` shows the UI in a normal window.

PIA: everything goes through `piactl`; the TCP/443 transport has to be pinned once (PIA app, or the quick
settings VPN page, no password prompt once deps.sh has installed the polkit rule) because `piactl` has no port setting.

Clipboard history keeps only the last 60 minutes (`clip-prune --daemon`, started by niri; `CLIP_MAX_MIN` changes it, `clip-prune --wipe` clears it).

Neovim: `lua/palette.lua` is rewritten by matugen and re-applied live in every running Neovim.

Agent utilities (for scripts and AI agents):
- `notify-me "message" [-t title] [-p priority] [-g tags]` sends an ntfy push using `~/.config/rice/.env`
  (`NTFY_URL`, `NTFY_PASSWORD`, optional `NTFY_USER`). `--dry-run` shows what would be sent.
- `caffeine-off [--lock]` switches caffeine / super caffeine off and turns the screen off at the same time.

Timer and todo: `Mod+Alt+T`, the chips next to the clock, the launcher (`t 25`, `todo buy milk`), or
`quickshell -c bar ipc call focus timer 25` / `focus todo "text"`.

`boot-preview` opens two windows that imitate the GRUB menu and the Plymouth passphrase screen (no root).
`vpn-autoconnect on|off|status` (or quick settings > VPN > "Connect at startup") controls the VPN connecting once per login.

Boot: `sudo bash deps.sh` also applies the GRUB theme and builds the extra Plymouth entry (`SKIP_BOOT_THEME=1` skips). This machine boots GRUB 2.16, which starts the unified kernel images (UKIs) in /boot/EFI/Linux.
`boot/switch-to-grub.sh` (called by deps.sh) reads the running loader from the LoaderInfo firmware variable and
does nothing when it already says GRUB; on systemd-boot it installs GRUB beside it and only makes it first after checks.
`sudo bash boot/boot-theme.sh status` first; `preview` draws pictures of both screens without root, `grub` themes the menu and tidies its entries (one per kernel image, extras under Advanced), `splash` puts a matching picture in the kernel
image, `plymouth` builds an extra boot entry with a spinner and a themed passphrase screen (normal entry untouched).
