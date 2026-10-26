#!/usr/bin/env bash
# Run with: sudo bash ~/deps.sh        (safe to re-run)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
USER_NAME=${SUDO_USER:?run through sudo}
UHOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
HERE=$(cd "$(dirname "$0")" && pwd)

echo "==> packages"
pacman -S --needed --noconfirm \
  matugen awww \
  swayidle swaylock \
  wireplumber pipewire-pulse \
  brightnessctl playerctl \
  xwayland-satellite xdg-desktop-portal-gnome \
  zsh-autosuggestions zsh-syntax-highlighting zsh-completions \
  eza bat fd ripgrep zoxide fzf btop fastfetch \
  cliphist wl-clipboard grim slurp satty libnotify \
  papirus-icon-theme capitaine-cursors \
  neovim tree-sitter-cli gcc make git unzip curl \
  wf-recorder

echo "==> network privacy helper (MAC / hostname / PIA transport)"
SRC="$UHOME/dotfiles/root"
[ -d "$SRC" ] || SRC="$HERE/root"
install -Dm755 "$SRC/usr/local/lib/rice/net-helper" /usr/local/lib/rice/net-helper
install -Dm644 "$SRC/usr/share/polkit-1/actions/org.rice.net.policy" /usr/share/polkit-1/actions/org.rice.net.policy
# world-readable mirror of the per-network MAC policy (/var/lib/iwd is root-only)
/usr/local/lib/rice/net-helper sync || true

echo "==> logind: react to the lid soon after a resume"
# logind ignores lid events for 30 s after resuming, so closing the lid right after opening it never slept
install -d /etc/systemd/logind.conf.d
printf '[Login]\nHoldoffTimeoutSec=3s\n' > /etc/systemd/logind.conf.d/rice-lid.conf
systemctl kill -s HUP systemd-logind || true

echo "==> SilentSDDM: follow the wallpaper"
T=/usr/share/sddm/themes/silent
if [ -d "$T" ]; then
  [ -f "$T/configs/rice.conf" ] || cp "$T/configs/default.conf" "$T/configs/rice.conf"
  [ -f "$UHOME/.cache/rice/sddm.conf" ] && cp "$UHOME/.cache/rice/sddm.conf" "$T/configs/rice.conf"
  cur=$(cat "$UHOME/.cache/rice/current" 2>/dev/null || true)
  if [ -f "$cur" ]; then cp "$cur" "$T/backgrounds/rice-bg.png"; else cp "$T/backgrounds/smoky.jpg" "$T/backgrounds/rice-bg.png"; fi
  chown "$USER_NAME": "$T/configs/rice.conf" "$T/backgrounds/rice-bg.png"
  chmod 644 "$T/configs/rice.conf" "$T/backgrounds/rice-bg.png"
  sed -i 's|^ConfigFile=configs/[A-Za-z0-9_-]*\.conf|ConfigFile=configs/rice.conf|' "$T/metadata.desktop"
  grep -n '^ConfigFile' "$T/metadata.desktop"
else
  echo "   (silent theme not found, skipping)"
fi

echo "==> boot loader"
# Does nothing if the machine already boots with GRUB (it reads the loader's own LoaderInfo variable).
# If it boots something else (systemd-boot) it installs GRUB next to it and only makes it first once checked.
# SKIP_GRUB=1 sudo bash deps.sh skips this step.
BOOT_DIR="$UHOME/dotfiles/boot"
[ -d "$BOOT_DIR" ] || BOOT_DIR="$HERE/boot"
if [ -f "$BOOT_DIR/switch-to-grub.sh" ]; then
  bash "$BOOT_DIR/switch-to-grub.sh" || echo "   (the GRUB step stopped; the boot setup is unchanged, see the message above)"
fi

echo "==> boot screens (GRUB theme + Plymouth passphrase entry)"
# SKIP_BOOT_THEME=1 sudo bash deps.sh skips this. The normal boot entry is never replaced:
# the GRUB theme only restyles the menu and Plymouth is built as an extra entry.
if [ -z "${SKIP_BOOT_THEME:-}" ] && [ -f "$BOOT_DIR/boot-theme.sh" ]; then
  bash "$BOOT_DIR/boot-theme.sh" grub || echo "   (GRUB theme step stopped, see above)"
  bash "$BOOT_DIR/boot-theme.sh" plymouth || echo "   (Plymouth step stopped, see above)"
fi

echo "==> login shell"
if [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != /usr/bin/zsh ]; then
  chsh -s /usr/bin/zsh "$USER_NAME" && echo "   login shell -> zsh (next login)"
fi

cat <<MSG

done. Next:
  * log out and back in (new PATH, cursor theme, xwayland-satellite)
  * if audio is silent:  systemctl --user enable --now pipewire pipewire-pulse wireplumber
MSG
