#!/usr/bin/env bash
# Installs the whole rice on an Arch machine: packages, root helpers, configs, wallpapers, themes, boot screens.
#
#   ./install.sh                 everything (asks for your sudo password for the root parts)
#   ./install.sh --no-root       only the user part: configs, wallpapers, themes (no sudo)
#   ./install.sh --no-boot       skip the GRUB / Plymouth steps
#   ./install.sh --no-wallpapers don't copy wallpapers/ into ~/Pictures/Wallpapers
#   ./install.sh --keyboard=chromebook|standard|auto   Alt as the main key (Chromebook) or Super; auto looks at the hardware
#
# Safe to re-run. Anything it replaces in $HOME is first copied to ~/.config-backup-<date>.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "run this as your normal user; it uses sudo where it needs root" >&2; exit 1; }
cd "$(dirname "$0")"
REPO=$PWD
# submodules (ai-container) when the repo was cloned without --recursive
git submodule update --init --recursive >/dev/null 2>&1 || true
ROOT=1; BOOT=1; WALL=1; KBD=auto
for a in "$@"; do
  case $a in
    --no-root) ROOT=0 ;;
    --no-boot) BOOT=0 ;;
    --no-wallpapers) WALL=0 ;;
    --keyboard=*) KBD=${a#--keyboard=} ;;
    -h|--help) sed -n 2,10p "$0"; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 1 ;;
  esac
done
say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
command -v pacman >/dev/null || { echo "this installer is for Arch Linux (pacman not found)" >&2; exit 1; }

# ---------- 1. root part: packages, helper + polkit rule, logind, SDDM theme, shell ----------
if [ "$ROOT" = 1 ]; then
  say "root part (packages, helpers, login screen) - sudo needed"
  sudo env SKIP_BOOT_THEME=1 bash "$REPO/deps.sh"
fi

# ---------- 2. configs ----------
say "configs -> $HOME"
bak="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
made_bak=0
while read -r f; do
  case "$f" in ./.config/librewolf/*) continue ;; esac     # handled below (the profile folder name differs per machine)
  if [ -e "$HOME/$f" ] && ! cmp -s "home/$f" "$HOME/$f"; then
    mkdir -p "$bak/$(dirname "$f")"; cp -a "$HOME/$f" "$bak/$f"; made_bak=1
  fi
  mkdir -p "$HOME/$(dirname "$f")"
  cp -a "home/$f" "$HOME/$f"
done < <(cd home && find . -type f)
[ "$made_bak" = 1 ] && echo "   replaced files were saved in $bak"
# absolute paths in the repo are stored as @HOME@ (older commits used /home/nyx): fill in this user's home
while read -r f; do
  case "$f" in ./.config/librewolf/*) continue ;; esac
  grep -Iq -e '@HOME@' -e '/home/nyx' "$HOME/$f" 2>/dev/null && sed -i -e "s|@HOME@|$HOME|g" -e "s|/home/nyx|$HOME|g" "$HOME/$f"
done < <(cd home && find . -type f)
chmod +x "$HOME"/.local/bin/* 2>/dev/null || true
mkdir -p "$HOME/Pictures/Screenshots" "$HOME/.cache/rice" "$HOME/.config/rice"
# ntfy credentials for `notify-me` (never tracked by git)
if [ ! -f "$HOME/.config/rice/.env" ]; then
  printf '# ntfy settings for notify-me\nNTFY_URL=\nNTFY_PASSWORD=\n#NTFY_USER=\n' > "$HOME/.config/rice/.env"
fi
chmod 600 "$HOME/.config/rice/.env"
# keyboard flavour: Chromebook keyboards get the Alt key as Mod (niri includes the generated keyboard.kdl)
"$HOME/.local/bin/keyboard-mode" "$KBD" || warn "keyboard-mode failed"
# larp mode writes its Ctrl+Q bind here while it runs; niri needs the file to exist
[ -f "$HOME/.config/niri/larp.kdl" ] || : > "$HOME/.config/niri/larp.kdl"
# profile picture (the lock screen shows it; SDDM gets the same file from deps.sh)
for f in root/usr/share/sddm/faces/"$USER".face.icon; do [ -f "$f" ] && [ ! -f "$HOME/.face" ] && cp "$f" "$HOME/.face"; done
# Claude Code hooks -> the bar (island pings when a session finishes or needs you, session list in the usage card)
python3 - <<'PY' || warn "could not add the Claude Code hooks"
import json, os
p = os.path.expanduser("~/.claude/settings.json")
try: d = json.load(open(p))
except FileNotFoundError: d = {}
cmd = {"type": "command", "command": os.path.expanduser("~/.local/bin/claude-island hook"), "timeout": 10}
hooks = d.setdefault("hooks", {})
for ev in ("SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"):
    lst = hooks.setdefault(ev, [])
    if not any("claude-island" in h.get("command", "") for e in lst for h in e.get("hooks", [])):
        lst.append({"hooks": [cmd]})
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY

# ---------- 3. wallpapers ----------
if [ "$WALL" = 1 ] && [ -d wallpapers ]; then
  say "wallpapers -> ~/Pictures/Wallpapers"
  mkdir -p "$HOME/Pictures/Wallpapers"
  cp -n wallpapers/* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
  echo "   $(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f | wc -l) wallpapers in place (existing files are never overwritten)"
fi

# ---------- 4. themes and shell bits ----------
say "GTK theme (Nordic-darker), zsh prompt"
if [ ! -d "$HOME/.themes/Nordic-darker" ] && [ -f assets/Nordic-darker.tar.xz ]; then
  mkdir -p "$HOME/.themes" && tar -xf assets/Nordic-darker.tar.xz -C "$HOME/.themes"
fi
if [ ! -f "$HOME/.local/share/zsh/powerlevel10k/powerlevel10k.zsh-theme" ]; then
  mkdir -p "$HOME/.local/share/zsh"
  git clone --depth 1 https://github.com/romkatv/powerlevel10k.git "$HOME/.local/share/zsh/powerlevel10k" || warn "could not download powerlevel10k (needs network); the prompt falls back to plain zsh"
fi

# ---------- 5. LibreWolf: theme files + the live-colour extension ----------
say "LibreWolf theme"
if command -v librewolf >/dev/null; then
  base="$HOME/.config/librewolf/librewolf"
  find_profile() { ls -d "$base"/*.default-release 2>/dev/null | head -1 || true; }
  prof=$(find_profile)
  if [ -z "$prof" ]; then            # never started: let it create its profile
    librewolf --headless about:blank >/dev/null 2>&1 & lwpid=$!
    for _ in $(seq 30); do prof=$(find_profile); [ -n "$prof" ] && break; sleep 1; done
    sleep 2; kill "$lwpid" 2>/dev/null || true; wait "$lwpid" 2>/dev/null || true
  fi
  if [ -n "$prof" ]; then
    src=home/.config/librewolf/librewolf/6yv4qbnb.default-release
    mkdir -p "$prof/chrome" "$prof/extensions"
    cp "$src/chrome/userChrome.css" "$src/chrome/userContent.css" "$prof/chrome/"
    [ -f "$prof/user.js" ] && ! cmp -s "$src/user.js" "$prof/user.js" && cp -a "$prof/user.js" "$prof/user.js.bak"
    cp "$src/user.js" "$prof/user.js"
    (cd home/.local/share/rice/librewolf-ext && rm -f "$prof/extensions/rice-theme@local.xpi" && python3 -m zipfile -c "$prof/extensions/rice-theme@local.xpi" manifest.json background.js)
    sed -i "s|librewolf/[^/]*\.default-release/chrome|librewolf/$(basename "$prof")/chrome|" "$HOME/.config/matugen/config.toml"
    echo "   profile: $(basename "$prof") (restart LibreWolf once to load it)"
  else
    warn "no LibreWolf profile found; start LibreWolf once and run ./install.sh --no-root again"
  fi
else
  echo "   librewolf is not installed, skipped"
fi

# ---------- 6. first colour scheme ----------
say "colours from a wallpaper"
first=""
for w in height-of-magic.png makeine.jpg; do [ -f "$HOME/Pictures/Wallpapers/$w" ] && { first="$HOME/Pictures/Wallpapers/$w"; break; }; done
[ -n "$first" ] || first=$(find -L "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | sort | head -1)
if [ -n "$first" ] && command -v matugen >/dev/null; then
  [ -f "$HOME/.cache/rice/current" ] || echo "$first" > "$HOME/.cache/rice/current"
  [ -f "$HOME/.cache/rice/mode" ] || echo dark > "$HOME/.cache/rice/mode"
  "$HOME/.local/bin/theme-mode" "$(cat "$HOME/.cache/rice/mode")" || warn "colour generation failed (is matugen installed?)"
else
  warn "no wallpaper or matugen yet; run 'wallpaper random' after logging in"
fi

# ---------- 7. user services, Neovim plugins ----------
say "audio services, Neovim plugins"
# the island's song player: mirror the film from song.tylerium.pro (needs node + chromium + ffmpeg)
"$HOME/.local/bin/still-fetch" || warn "could not fetch still@server (run ~/.local/bin/still-fetch with network)"
# Spotify theme: spicetify from the official release (checksum-verified); start Spotify with `spotify` afterwards
"$HOME/.local/bin/spicetify-fetch" || warn "could not install spicetify (run ~/.local/bin/spicetify-fetch with network)"
systemctl --user enable --now pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || warn "could not enable pipewire for this session (do it after logging in)"
if command -v nvim >/dev/null; then
  timeout 300 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "Neovim plugin install did not finish (open nvim once with network)"
fi

# ---------- 8. ai-container: `container`, Alpine boxes for AI agents (its own repo, a submodule) ----------
if [ -x "$REPO/ai-container/install.sh" ]; then
  say "ai-container"
  if [ "$ROOT" = 1 ]; then "$REPO/ai-container/install.sh" || warn "container setup stopped (run ai-container/install.sh again)"
  else "$REPO/ai-container/install.sh" --no-root; fi
fi

# ---------- 9. boot screens (need the colours from step 6) ----------
if [ "$ROOT" = 1 ] && [ "$BOOT" = 1 ]; then
  say "boot screens (GRUB theme + Plymouth entry) - sudo needed"
  sudo bash "$REPO/boot/switch-to-grub.sh" || warn "GRUB check stopped; boot setup unchanged"
  sudo bash "$REPO/boot/boot-theme.sh" plymouth || warn "Plymouth step stopped (see above); boot setup unchanged"
  sudo bash "$REPO/boot/boot-theme.sh" grub || warn "GRUB theme step stopped (see above)"
fi

cat <<MSG

done.
  * log out and back in (new PATH, cursor theme, quickshell bar, wallpaper daemon)
  * LibreWolf: restart it once so the theme extension loads
  * ntfy push notifications: put NTFY_URL / NTFY_PASSWORD into ~/.config/rice/.env
  * Ctrl+\` changes the wallpaper (colours follow), Mod+Shift+W opens the picker
MSG
