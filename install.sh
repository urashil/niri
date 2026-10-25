#!/usr/bin/env bash
# Put the repo's config into $HOME (backs up anything it replaces to ~/.config-backup-<date>),
# then run the root part:  sudo bash deps.sh
set -euo pipefail
cd "$(dirname "$0")"
bak="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
(cd home && find . -type f) | while read -r f; do
  if [ -e "$HOME/$f" ]; then mkdir -p "$bak/$(dirname "$f")"; cp -a "$HOME/$f" "$bak/$f"; fi
  mkdir -p "$HOME/$(dirname "$f")"
  cp -a "home/$f" "$HOME/$f"
done
mkdir -p ~/Pictures/Wallpapers ~/Pictures/Screenshots ~/.cache/rice
echo "config installed (backup: $bak). Now: sudo bash deps.sh, add wallpapers to ~/Pictures/Wallpapers, run: wallpaper random"
