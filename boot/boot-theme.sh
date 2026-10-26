#!/usr/bin/env bash
# boot-theme.sh: make the boot screens match the lock screen (wallpaper blur + accent colour).
#
#   sudo bash boot-theme.sh status      read-only: what boots this machine and what each step would do
#   sudo bash boot-theme.sh splash      matching splash picture in your kernel image (UKI). Backup kept.
#   sudo bash boot-theme.sh plymouth    animation + disk-passphrase screen, built as an EXTRA boot entry.
#                                       Your normal entry is not touched, so a mistake costs nothing.
#   sudo bash boot-theme.sh grub        a GRUB theme. Only does anything if GRUB is really your loader.
#   add --dry-run to any of them to see the commands without running them (works without sudo)
#
# Colours and the wallpaper come from your rice (~/.config/quickshell/bar/colors.json, ~/.cache/rice/current).
set -euo pipefail

DRY=0; CMD="${1:-status}"; shift || true
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=1; done
[ "$CMD" = "--dry-run" ] && { DRY=1; CMD=status; }

if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then echo "run with sudo (or add --dry-run)" >&2; exit 1; fi
U="${SUDO_USER:-$USER}"; UH=$(getent passwd "$U" | cut -d: -f6)
COLORS="$UH/.config/quickshell/bar/colors.json"
WALL="$(cat "$UH/.cache/rice/current" 2>/dev/null || true)"
KVER_IMG=/boot/vmlinuz-linux-hardened
UKI_DIR=/boot/EFI/Linux
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }
say() { printf '\n==> %s\n' "$*"; }
need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }

# ---- palette ----
[ -r "$COLORS" ] || { echo "no $COLORS (run: wallpaper restore)" >&2; exit 1; }
col() { python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].lstrip('#'))" "$COLORS" "$1"; }
SURFACE=$(col surface); PRIMARY=$(col primary); CONTAINER=$(col primaryContainer); TEXT=$(col text); HIGH=$(col surfaceHigh)
rgb() { printf '%d %d %d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }

# ---- what boots this machine ----
detect() {
  LOADER="unknown"
  if command -v efibootmgr >/dev/null && efibootmgr -v 2>/dev/null | grep -qi 'systemd-boot\|systemd\\systemd'; then LOADER="systemd-boot"; fi
  if [ -f /boot/grub/grub.cfg ] && efibootmgr -v 2>/dev/null | grep -qi grub; then LOADER="grub"; fi
  [ "$LOADER" = unknown ] && [ -d /boot/loader ] && LOADER="systemd-boot"
  UKI=0; grep -q '^default_uki=' /etc/mkinitcpio.d/linux-hardened.preset 2>/dev/null && UKI=1
}

# ---- artwork: the lock screen look (blurred, darkened wallpaper + an accent ring) ----
make_splash() {   # $1 = output .bmp
  need ffmpeg; need rsvg-convert
  [ -f "$WALL" ] || { echo "no wallpaper recorded in ~/.cache/rice/current" >&2; exit 1; }
  ffmpeg -loglevel error -y -i "$WALL" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=34,eq=brightness=-0.22:saturation=1.05" "$WORK/bg.png"
  cat > "$WORK/ring.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <circle cx="100" cy="100" r="46" fill="none" stroke="#$HIGH" stroke-opacity="0.55" stroke-width="7"/>
  <circle cx="100" cy="100" r="46" fill="none" stroke="#$PRIMARY" stroke-width="7" stroke-linecap="round" stroke-dasharray="110 180" transform="rotate(-70 100 100)"/>
  <circle cx="100" cy="100" r="9" fill="#$PRIMARY"/>
</svg>
SVG
  rsvg-convert -o "$WORK/ring.png" "$WORK/ring.svg"
  ffmpeg -loglevel error -y -i "$WORK/bg.png" -i "$WORK/ring.png" -filter_complex "[0][1]overlay=(W-w)/2:(H-h)/2" -pix_fmt bgr24 "$1"
}

backup() { [ -e "$1" ] && [ ! -e "$1.bak" ] && run cp -a "$1" "$1.bak" || true; }

# ================= commands =================
status() {
  detect
  say "this machine"
  echo "boot loader   : $LOADER"
  echo "kernel images : $([ "$UKI" = 1 ] && echo "unified kernel image (UKI) in $UKI_DIR" || echo "classic initramfs")"
  echo "disk          : $(lsblk -no TYPE,FSTYPE 2>/dev/null | grep -q crypto_LUKS && echo "encrypted root (passphrase asked at boot)" || echo "not encrypted")"
  echo "plymouth      : $(pacman -Q plymouth 2>/dev/null || echo "not installed")"
  echo "cmdline       : $(cat /proc/cmdline)"
  say "what each step does"
  echo "splash   : rebuilds your UKI with a splash picture matching the lock screen (backup: *.efi.bak)."
  echo "plymouth : installs plymouth + a themed 'rice' spinner, builds ${UKI_DIR}/arch-linux-hardened-splash.efi as an extra entry."
  echo "grub     : $([ "$LOADER" = grub ] && echo "GRUB is in use: writes /boot/grub/themes/rice" || echo "skipped, your loader is $LOADER so a GRUB theme would do nothing")"
}

splash() {
  detect
  [ "$UKI" = 1 ] || { echo "this needs the UKI setup (default_uki in the preset); yours looks classic" >&2; exit 1; }
  say "making the splash picture"
  make_splash "$WORK/splash.bmp"
  run install -Dm644 "$WORK/splash.bmp" /usr/share/systemd/bootctl/splash-rice.bmp
  PRESET=/etc/mkinitcpio.d/linux-hardened.preset
  backup "$PRESET"
  backup "$UKI_DIR/arch-linux-hardened.efi"
  say "pointing the preset at it and rebuilding the UKI"
  run sed -i 's|^default_options="--splash [^"]*"|default_options="--splash /usr/share/systemd/bootctl/splash-rice.bmp"|' "$PRESET"
  run mkinitcpio -p linux-hardened
  echo; echo "done. Reboot to see it. To go back: sudo cp $PRESET.bak $PRESET && sudo mkinitcpio -p linux-hardened"
}

plymouth() {
  detect
  [ "$UKI" = 1 ] || { echo "plymouth step is written for the UKI setup" >&2; exit 1; }
  need ffmpeg
  say "installing plymouth"
  run pacman -S --needed --noconfirm plymouth
  T=/usr/share/plymouth/themes
  say "building the 'rice' theme from the stock spinner"
  if [ "$DRY" = 1 ] && [ ! -d "$T/spinner" ]; then echo "(dry run: plymouth not installed here, skipping theme build)"; else
    run rm -rf "$T/rice"; run cp -a "$T/spinner" "$T/rice"
    run mv "$T/rice/spinner.plymouth" "$T/rice/rice.plymouth"
    read -r R G B <<<"$(rgb "$PRIMARY")"
    for f in "$T"/rice/animation-*.png "$T"/rice/throbber-*.png; do   # tint the white throbber to the accent colour, keep alpha
      ffmpeg -loglevel error -y -i "$f" -vf "format=rgba,colorchannelmixer=rr=$(python3 -c "print($R/255)"):gg=$(python3 -c "print($G/255)"):bb=$(python3 -c "print($B/255)")" "$WORK/t.png" && run install -m644 "$WORK/t.png" "$f"
    done
    run sed -i -e "s|^Name=.*|Name=Rice|" -e "s|^ImageDir=.*|ImageDir=$T/rice|" \
        -e "s|^BackgroundStartColor=.*|BackgroundStartColor=0x$SURFACE|" -e "s|^BackgroundEndColor=.*|BackgroundEndColor=0x$SURFACE|" \
        -e "s|^ProgressBarBackgroundColor=.*|ProgressBarBackgroundColor=0x$HIGH|" -e "s|^ProgressBarForegroundColor=.*|ProgressBarForegroundColor=0x$PRIMARY|" "$T/rice/rice.plymouth"
    run plymouth-set-default-theme rice
  fi
  say "config for the extra image: the stock hooks with 'plymouth' after 'udev'"
  if [ "$DRY" = 1 ]; then echo "+ sed HOOKS in /etc/mkinitcpio.conf -> /etc/mkinitcpio-splash.conf"; else
    sed -E '/^HOOKS=/ s/\budev\b/udev plymouth/' /etc/mkinitcpio.conf > /etc/mkinitcpio-splash.conf
    grep '^HOOKS=' /etc/mkinitcpio-splash.conf
    grep -q 'udev plymouth' /etc/mkinitcpio-splash.conf || { echo "could not insert the plymouth hook; stopping before anything is built" >&2; exit 1; }
  fi
  say "splash picture + command line"
  make_splash "$WORK/splash.bmp"
  run install -Dm644 "$WORK/splash.bmp" /usr/share/systemd/bootctl/splash-rice.bmp
  echo "$(cat /proc/cmdline) quiet splash loglevel=3" > "$WORK/cmdline"
  say "building the extra entry (your normal entry is not touched)"
  run mkinitcpio -c /etc/mkinitcpio-splash.conf -k "$KVER_IMG" -U "$UKI_DIR/arch-linux-hardened-splash.efi" --cmdline "$WORK/cmdline" --splash /usr/share/systemd/bootctl/splash-rice.bmp
  cat <<MSG

done. Next:
  1. reboot and choose "arch-linux-hardened-splash" in the systemd-boot menu
     (hold Space or press a key right after the firmware logo to get the menu).
  2. check you can type your disk passphrase and reach the login screen.
  3. if all is well:  sudo bootctl set-default arch-linux-hardened-splash.efi
  4. if anything is wrong, just boot the normal entry again, nothing else was changed.
     remove it with:  sudo rm $UKI_DIR/arch-linux-hardened-splash.efi
MSG
}

grubtheme() {
  detect
  if [ "$LOADER" != grub ]; then echo "GRUB does not look like your boot loader ($LOADER), so a GRUB theme would do nothing. Skipping."; return 0; fi
  need ffmpeg; need rsvg-convert; need grub-mkfont
  D=/boot/grub/themes/rice
  say "building the GRUB theme"
  run mkdir -p "$D"
  ffmpeg -loglevel error -y -i "$WALL" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=34,eq=brightness=-0.22" "$WORK/background.png"
  run install -m644 "$WORK/background.png" "$D/background.png"
  FONT=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font")
  for s in 16 20; do grub-mkfont -s $s -o "$WORK/f$s.pf2" "$FONT"; run install -m644 "$WORK/f$s.pf2" "$D/font$s.pf2"; done
  cat > "$WORK/theme.txt" <<THEME
desktop-image: "background.png"
desktop-image-scale-method: "crop"
desktop-color: "#$SURFACE"
title-text: ""
terminal-font: "JetBrainsMono Nerd Font Regular 16"
+ boot_menu {
  left = 30%
  width = 40%
  top = 32%
  height = 40%
  item_font = "JetBrainsMono Nerd Font Regular 20"
  selected_item_font = "JetBrainsMono Nerd Font Regular 20"
  item_color = "#$TEXT"
  selected_item_color = "#$PRIMARY"
  item_height = 44
  item_padding = 14
  item_spacing = 8
  icon_width = 0
  scrollbar = false
}
+ progress_bar {
  id = "__timeout__"
  left = 30%
  width = 40%
  top = 80%
  height = 8
  fg_color = "#$PRIMARY"
  bg_color = "#$HIGH"
  border_color = "#$HIGH"
  text = ""
}
THEME
  run install -m644 "$WORK/theme.txt" "$D/theme.txt"
  backup /etc/default/grub
  run sed -i -e '/^GRUB_THEME=/d' /etc/default/grub
  if [ "$DRY" = 1 ]; then echo "+ echo GRUB_THEME=$D/theme.txt >> /etc/default/grub"; else echo "GRUB_THEME=\"$D/theme.txt\"" >> /etc/default/grub; fi
  run grub-mkconfig -o /boot/grub/grub.cfg
  echo "done. Reboot to see the theme. To undo: restore /etc/default/grub.bak and run grub-mkconfig again."
}

case "$CMD" in
  status) status ;;
  splash) splash ;;
  plymouth) plymouth ;;
  grub) grubtheme ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
