# dotfiles (local)

niri + quickshell bar, matugen colours from the wallpaper, kitty/zsh/p10k, SilentSDDM synced to the wallpaper.

- `sync.sh`    copy live config from `$HOME` into `home/`
- `install.sh` copy `home/` back onto a fresh machine
- `deps.sh`    root part: packages, network-privacy helper + polkit rule, SDDM theme permissions
- `root/`      files installed as root by `deps.sh`

Keybinds worth knowing: `Ctrl+\`` next wallpaper, `Mod+Shift+W` picker, `Mod+Space` launcher
(`w ` windows, `c ` clipboard, `> ` run, `s ` web, maths inline), `Alt+Tab` window switcher,
`Mod+A` quick settings (Wi-Fi, Bluetooth, VPN, privacy, weather), `Mod+N` notifications,
`Mod+X` power menu, `Mod+Y` clipboard, `Mod+Shift+S` screenshot+annotate, ``Mod+` `` scratch terminal,
`Mod+Shift+D` do not disturb, `Mod+Shift+B` caffeine, `Mod+Shift+T` light/dark, `Super+Alt+L` lock.

Lock screen: `~/.local/bin/lock` runs the quickshell lock (`~/.config/quickshell/lock`) and falls back to
swaylock if it does not engage within 4 s. `LOCK_TEST=1 lock` auto-unlocks after 6 s for testing,
`LOCK_PREVIEW=1 quickshell -c lock` shows the UI in a normal window.

PIA: everything goes through `piactl`; the TCP/443 transport has to be pinned once (PIA app, or the quick
settings VPN page, no password prompt once deps.sh has installed the polkit rule) because `piactl` has no port setting.

Neovim: `lua/palette.lua` is rewritten by matugen and re-applied live in every running Neovim.

Agent utilities (for scripts and AI agents):
- `notify-me "message" [-t title] [-p priority] [-g tags]` sends an ntfy push using `~/.config/rice/.env`
  (`NTFY_URL`, `NTFY_PASSWORD`, optional `NTFY_USER`). `--dry-run` shows what would be sent.
- `caffeine-off [--lock]` switches caffeine / super caffeine off and turns the screen off at the same time.

Timer and todo: `Mod+Alt+T`, the chips next to the clock, the launcher (`t 25`, `todo buy milk`), or
`quickshell -c bar ipc call focus timer 25` / `focus todo "text"`.

Boot look: `sudo bash boot/boot-theme.sh status` first. This machine boots systemd-boot + UKIs, so `splash`
(picture in the kernel image) and `plymouth` (extra boot entry, normal entry untouched) apply; `grub` only if GRUB is real.
