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
  .local/bin/clip-prune .local/bin/vpn-autoconnect .local/bin/boot-preview .local/bin/librewolf-theme-host .local/bin/network-login .local/bin/pia-killswitch .local/bin/still-film .local/bin/still-fetch .local/bin/song .local/bin/still .local/bin/film
  .config/quickshell/bootpreview
  .config/rice/wallpaper-modes.json
  .config/rice/network-login.sh .config/spotify-launcher.conf
  .local/share/rice/librewolf-ext
  .local/share/rice/emoji.tsv .local/share/rice/still-at-server/frame.html .local/share/rice/still-at-server/frame.js
  .librewolf/native-messaging-hosts/rice_theme.json
)
for f in "${FILES[@]}"; do
  mkdir -p "home/$(dirname "$f")"
  rm -rf "home/$f"
  cp -a "$HOME/$f" "home/$f"
done
rm -f home/.config/quickshell/bar/colors.json
# absolute home paths become a placeholder that install.sh fills in for whoever installs it
grep -rIl "$HOME" home 2>/dev/null | xargs -r sed -i "s|$HOME|@HOME@|g"
cp -a ~/deps.sh deps.sh
# wallpapers (generated placeholders named *.ai are left out), the GTK theme archive, the display manager config
rm -rf wallpapers && mkdir -p wallpapers
find -L "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f ! -name '*.ai' -exec cp -p {} wallpapers/ \;
mkdir -p assets root/etc
[ -f "$HOME/.themes/Nordic-darker.tar.xz" ] && cp -p "$HOME/.themes/Nordic-darker.tar.xz" assets/
[ -r /etc/sddm.conf ] && cp /etc/sddm.conf root/etc/sddm.conf
echo "synced"
