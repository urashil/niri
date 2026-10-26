#!/usr/bin/env bash
# Copy the live config from $HOME into this repo (generated colour files are skipped).
set -euo pipefail
cd "$(dirname "$0")"
FILES=(
  .zshrc .p10k.zsh .p10k-colors.zsh
  .config/niri/config.kdl
  .config/kitty/kitty.conf
  .config/fuzzel/fuzzel.ini
  .config/matugen
  .config/quickshell/bar
  .config/quickshell/lock
  .config/nvim
  .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini
  .config/btop/btop.conf
  .config/fastfetch/config.jsonc
  .config/librewolf/librewolf/6yv4qbnb.default-release/chrome/userChrome.css
  .config/librewolf/librewolf/6yv4qbnb.default-release/chrome/userContent.css
  .config/librewolf/librewolf/6yv4qbnb.default-release/user.js
  .local/bin/lock .local/bin/lid-close .local/bin/rec .local/bin/notify-me .local/bin/caffeine-off .local/bin/theme-mode .local/bin/wallpaper .local/bin/shot .local/bin/clip .local/bin/scratch
)
for f in "${FILES[@]}"; do
  mkdir -p "home/$(dirname "$f")"
  rm -rf "home/$f"
  cp -a "$HOME/$f" "home/$f"
done
rm -f home/.config/quickshell/bar/colors.json
cp -a ~/deps.sh deps.sh
echo "synced"
