#!/usr/bin/env bash
# boot-theme.sh: make the boot screens match the lock screen
# (this machine boots GRUB 2.16 -> unified kernel images; the script checks the running loader itself) (wallpaper blur + accent colour).
#
#   sudo bash boot-theme.sh status      read-only: what boots this machine and what each step would do
#   sudo bash boot-theme.sh splash      matching splash picture in your kernel image (UKI). Backup kept.
#   sudo bash boot-theme.sh plymouth    animation + disk-passphrase screen, built as an EXTRA boot entry.
#                                       Your normal entry is not touched, so a mistake costs nothing.
#   sudo bash boot-theme.sh grub        a GRUB theme (menu background, fonts, colours). Only if GRUB is the running loader.
#   add --dry-run to any of them to see the commands without running them (works without sudo)
#
# Colours and the wallpaper come from your rice (~/.config/quickshell/bar/colors.json, ~/.cache/rice/current).
set -euo pipefail

DRY=0; CMD="${1:-status}"; shift || true
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=1; done
[ "$CMD" = preview ] && DRY=1
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
TEXTDIM=$(col textDim); FGCONTAINER=$(col fgContainer); SURFACE=$(col surface); PRIMARY=$(col primary); CONTAINER=$(col primaryContainer); TEXT=$(col text); HIGH=$(col surfaceHigh)
rgb() { printf '%d %d %d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }

# ---- what boots this machine ----
detect() {
  # the running loader announces itself in the LoaderInfo firmware variable (entry names in the firmware menu can be stale)
  LOADER="unknown"
  info=$(tail -c +5 /sys/firmware/efi/efivars/LoaderInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\0')
  case "$info" in
    GRUB*) LOADER="grub" ;;
    systemd-boot*) LOADER="systemd-boot" ;;
  esac
  LOADER_INFO="$info"
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


# ---- plymouth artwork: wallpaper, spinner, passphrase entry (same look + ring geometry as the splash picture) ----
make_plymouth_art() {   # $1 = output dir
  local o="$1"; mkdir -p "$o"
  need ffmpeg; need rsvg-convert
  [ -f "$WALL" ] || { echo "no wallpaper recorded in ~/.cache/rice/current" >&2; exit 1; }
  ffmpeg -loglevel error -y -i "$WALL" -vf "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,gblur=sigma=22,eq=brightness=-0.22:saturation=1.05" "$o/bg.png"
  cat > "$WORK/track.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <circle cx="100" cy="100" r="46" fill="none" stroke="#$HIGH" stroke-opacity="0.55" stroke-width="7"/>
</svg>
SVG
  cat > "$WORK/arc.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <circle cx="100" cy="100" r="46" fill="none" stroke="#$PRIMARY" stroke-width="7" stroke-linecap="round" stroke-dasharray="110 180"/>
</svg>
SVG
  cat > "$WORK/dot.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><circle cx="9" cy="9" r="9" fill="#$PRIMARY"/></svg>
SVG
  cat > "$WORK/entry.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="440" height="56" viewBox="0 0 440 56">
  <rect x="1" y="1" width="438" height="54" rx="27" fill="#$HIGH" fill-opacity="0.88" stroke="#$PRIMARY" stroke-opacity="0.55" stroke-width="1.5"/>
</svg>
SVG
  cat > "$WORK/bullet.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><circle cx="7" cy="7" r="6" fill="#$PRIMARY"/></svg>
SVG
  cat > "$WORK/label.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="440" height="30" viewBox="0 0 440 30">
  <text x="220" y="21" text-anchor="middle" font-family="JetBrainsMono Nerd Font" font-size="18" fill="#$TEXT" fill-opacity="0.8">Unlock your disk</text>
</svg>
SVG
  local n; for n in track arc dot entry bullet label; do rsvg-convert -o "$o/$n.png" "$WORK/$n.svg"; done
  local R G B; read -r R G B <<<"$(python3 -I -c "import sys; h=sys.argv[1]; print(*(round(int(h[i:i+2],16)/255,3) for i in (0,2,4)))" "$SURFACE")"
  cat > "$o/rice.script" <<'PLYSCRIPT'
# rice: boot screen that matches the lock screen. Generated by boot-theme.sh, do not edit in place.
Window.SetBackgroundTopColor(@R@, @G@, @B@);
Window.SetBackgroundBottomColor(@R@, @G@, @B@);

sw = Window.GetWidth();
sh = Window.GetHeight();
cx = Window.GetX() + sw / 2;
cy = Window.GetY() + sh / 2;

# blurred, darkened wallpaper
bg_img = Image("bg.png");
bg = Sprite(bg_img.Scale(sw, sh));
bg.SetPosition(Window.GetX(), Window.GetY(), -100);

# spinner: fixed track + a rotating arc + a breathing centre dot (same geometry as the firmware splash picture)
arc_img = Image("arc.png");
track_img = Image("track.png");
dot_img = Image("dot.png");
track = Sprite(track_img);
track.SetPosition(cx - track_img.GetWidth() / 2, cy - track_img.GetHeight() / 2, 1);
arc = Sprite(arc_img);
arc.SetPosition(cx - arc_img.GetWidth() / 2, cy - arc_img.GetHeight() / 2, 2);
dot = Sprite(dot_img);
dot.SetPosition(cx - dot_img.GetWidth() / 2, cy - dot_img.GetHeight() / 2, 3);

# passphrase prompt: label + rounded entry with a dot per typed character
label_img = Image("label.png");
entry_img = Image("entry.png");
bullet_img = Image("bullet.png");
ex = cx - entry_img.GetWidth() / 2;
ey = cy + 134;
lx = cx - label_img.GetWidth() / 2;
ly = cy + 92;
max_bullets = 17;

label = Sprite(label_img);
entry = Sprite(entry_img);
label.SetOpacity(0);
entry.SetOpacity(0);
for (i = 0; i < max_bullets; i = i + 1) {
  bullets[i] = Sprite(bullet_img);
  bullets[i].SetOpacity(0);
}

angle = 0;
tick = 0;
prompt_target = 0;
prompt_alpha = 0;
bullet_count = 0;
prev_bullets = -1;
shake = 0;
shake_t = 0;

fun refresh_callback() {
  tick = tick + 1;
  angle = angle + 0.085;
  rot = arc_img.Rotate(angle);
  arc.SetImage(rot);
  arc.SetPosition(cx - rot.GetWidth() / 2, cy - rot.GetHeight() / 2, 2);
  dot.SetOpacity(0.7 + 0.3 * Math.Sin(tick * 0.06));

  prompt_alpha = prompt_alpha + (prompt_target - prompt_alpha) * 0.18;

  off = 0;
  if (shake > 0.5) {
    off = Math.Sin(shake_t * 1.2) * shake;
    shake = shake * 0.9;
    shake_t = shake_t + 1;
  } else {
    shake = 0;
  }

  label.SetPosition(lx + off, ly, 10);
  label.SetOpacity(prompt_alpha);
  entry.SetPosition(ex + off, ey, 10);
  entry.SetOpacity(prompt_alpha);
  for (i = 0; i < max_bullets; i = i + 1) {
    bullets[i].SetPosition(ex + off + 34 + i * 22, ey + entry_img.GetHeight() / 2 - bullet_img.GetHeight() / 2, 11);
    if (i < bullet_count) {
      bullets[i].SetOpacity(prompt_alpha);
    } else {
      bullets[i].SetOpacity(0);
    }
  }
}
Plymouth.SetRefreshFunction(refresh_callback);

fun display_password_callback(prompt, count) {
  # the box empties right after a submit: a wrong passphrase shakes it
  if (prev_bullets > 1 && count == 0) {
    shake = 14;
    shake_t = 0;
  }
  prev_bullets = count;
  bullet_count = count;
  prompt_target = 1;
}
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun display_normal_callback() {
  prompt_target = 0;
  prev_bullets = -1;
  bullet_count = 0;
}
Plymouth.SetDisplayNormalFunction(display_normal_callback);
PLYSCRIPT
  sed -i -e "s/@R@/$R/g" -e "s/@G@/$G/g" -e "s/@B@/$B/g" "$o/rice.script"
}

# ---- GRUB artwork: card, selection pill, fonts ----
make_grub_art() {   # $1 = output dir
  local o="$1"; mkdir -p "$o"
  need ffmpeg; need rsvg-convert; need magick; need grub-mkfont
  [ -f "$WALL" ] || { echo "no wallpaper recorded in ~/.cache/rice/current" >&2; exit 1; }
  ffmpeg -loglevel error -y -i "$WALL" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=34,eq=brightness=-0.26:saturation=1.05" "$o/background.png"
  # 9-slice boxes: menu card (r26) and selection pill (r22)
  cat > "$WORK/card.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="104" height="104"><rect x="1" y="1" width="102" height="102" rx="26" fill="#$SURFACE" fill-opacity="0.80" stroke="#$HIGH" stroke-width="1.5"/></svg>
SVG
  cat > "$WORK/pill.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" rx="22" fill="#$CONTAINER"/></svg>
SVG
  rsvg-convert -o "$WORK/card.png" "$WORK/card.svg"
  rsvg-convert -o "$WORK/pill.png" "$WORK/pill.svg"
  slice() {   # $1 source  $2 prefix  $3 corner radius  $4 size
    local src=$1 p=$2 r=$3 sz=$4 far=$(( $4 - $3 )) mid=$(( $4 / 2 ))
    magick "$src" -crop ${r}x${r}+0+0       +repage "$o/${p}_nw.png"
    magick "$src" -crop 1x${r}+${mid}+0     +repage "$o/${p}_n.png"
    magick "$src" -crop ${r}x${r}+${far}+0  +repage "$o/${p}_ne.png"
    magick "$src" -crop ${r}x1+0+${mid}     +repage "$o/${p}_w.png"
    magick "$src" -crop 1x1+${mid}+${mid}   +repage "$o/${p}_c.png"
    magick "$src" -crop ${r}x1+${far}+${mid} +repage "$o/${p}_e.png"
    magick "$src" -crop ${r}x${r}+0+${far}  +repage "$o/${p}_sw.png"
    magick "$src" -crop 1x${r}+${mid}+${far} +repage "$o/${p}_s.png"
    magick "$src" -crop ${r}x${r}+${far}+${far} +repage "$o/${p}_se.png"
  }
  slice "$WORK/card.png" menu 26 104
  slice "$WORK/pill.png" select 22 100
  local FONT; FONT=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font")
  [ -f "$FONT" ] || { echo "JetBrainsMono Nerd Font not found" >&2; exit 1; }
  local sz; for sz in 16 20 36; do grub-mkfont -s $sz -o "$o/font$sz.pf2" "$FONT" 2>/dev/null; done
  # the theme must use the exact name stored inside the .pf2 (its NAME section)
  pf2name() { python3 -I - "$1" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
i = 12                                   # "FILE" + length + "PFF2"
while i + 8 <= len(d):
    tag, ln = d[i:i+4], int.from_bytes(d[i+4:i+8], "big")
    if tag == b"NAME":
        print(d[i+8:i+8+ln].split(b"\0")[0].decode()); break
    i += 8 + (ln if tag != b"DATA" else 0)
    if tag == b"DATA": break
PY
  }
  F16=$(pf2name "$o/font16.pf2"); F20=$(pf2name "$o/font20.pf2"); F36=$(pf2name "$o/font36.pf2")
  [ -n "$F16" ] && [ -n "$F20" ] && [ -n "$F36" ] || { echo "could not read the font names from the generated .pf2 files" >&2; exit 1; }
  local HOST; HOST=$(cat /etc/hostname 2>/dev/null || echo arch)
  cat > "$o/theme.txt" <<THEME
desktop-image: "background.png"
desktop-image-scale-method: "crop"
desktop-color: "#$SURFACE"
title-text: ""
terminal-font: "$F16"

+ label {
  left = 0
  top = 17%
  width = 100%
  align = "center"
  text = "$HOST"
  font = "$F36"
  color = "#$PRIMARY"
}
+ label {
  left = 0
  top = 24%
  width = 100%
  align = "center"
  text = "choose what to start"
  font = "$F16"
  color = "#$TEXTDIM"
}
+ boot_menu {
  left = 50%-240
  width = 480
  top = 32%
  height = 380
  menu_pixmap_style = "menu_*"
  selected_item_pixmap_style = "select_*"
  item_font = "$F20"
  selected_item_font = "$F20"
  item_color = "#$TEXT"
  selected_item_color = "#$FGCONTAINER"
  item_height = 44
  item_padding = 18
  item_spacing = 6
  icon_width = 0
  item_icon_space = 0
  scrollbar = false
}
+ label {
  id = "__timeout__"
  left = 0
  top = 84%
  width = 100%
  align = "center"
  text = "starting in %d s, press any key to stay"
  font = "$F16"
  color = "#$TEXTDIM"
}
THEME
}

# ---- GRUB menu entries: clean list instead of the stock generators ----
GRUB_ENTRIES_SCRIPT='#!/bin/sh
# written by boot-theme.sh: one tidy entry per unified kernel image, the rest under "Advanced".
UKI_DIR="${RICE_UKI_DIR:-/boot/EFI/Linux}"
ESP_UUID="${RICE_ESP_UUID:-$(grub-probe -t fs_uuid /boot 2>/dev/null)}"
[ -n "$ESP_UUID" ] || exit 0
title() {
  case "$1" in
    arch-linux-hardened.efi) echo "Arch Linux" ;;
    arch-linux-hardened-splash.efi) echo "Arch Linux  (Plymouth)" ;;
    *) echo "$1" | sed "s/\.efi\$//" ;;
  esac
}
entry() {   # $1 file  $2 title  $3 indent
  cat <<EOF
$3menuentry "$2" --class arch --class gnu-linux --class os {
$3  insmod part_gpt
$3  insmod fat
$3  insmod chain
$3  search --no-floppy --fs-uuid --set=root $ESP_UUID
$3  chainloader /EFI/Linux/$1
$3}
EOF
}
main=""; adv=""
for f in "$UKI_DIR"/*.efi; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    arch-linux-hardened.efi|arch-linux-hardened-splash.efi) main="$main $b" ;;
    *) adv="$adv $b" ;;
  esac
done
# the plain image first (it is the default), then the Plymouth one
for want in arch-linux-hardened.efi arch-linux-hardened-splash.efi; do
  for b in $main; do [ "$b" = "$want" ] && entry "$b" "$(title "$b")" ""; done
done
if [ -n "$adv" ]; then
  echo "submenu \"Advanced\" {"
  for b in $adv; do entry "$b" "$(title "$b")" "  "; done
  echo "}"
fi
'
GRUB_POWER_SCRIPT='#!/bin/sh
# written by boot-theme.sh: restart / shut down entries at the end of the menu
cat <<EOF
menuentry "Restart" --class restart { reboot }
menuentry "Shut down" --class shutdown { halt }
EOF
'

# Approximate pictures of the GRUB menu and the Plymouth passphrase screen, built from the real assets (no root needed).
preview() {
  local out="${1:-$PWD/boot-preview}"; mkdir -p "$out"
  make_grub_art "$WORK/gt"; make_plymouth_art "$WORK/ply"
  local FONT; FONT=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font")
  local HOST; HOST=$(cat /etc/hostname 2>/dev/null || echo arch)
  # GRUB: card 480x380 at (720,346); pill at the first row
  magick "$WORK/gt/background.png" \
    \( "$WORK/card.png" -resize 480x380! \) -geometry +720+346 -composite \
    \( "$WORK/pill.png" -resize 432x44! \) -geometry +744+370 -composite \
    -font "$FONT" -fill "#$PRIMARY" -pointsize 36 -gravity North -annotate +0+184 "$HOST" \
    -fill "#$TEXTDIM" -pointsize 16 -annotate +0+260 "choose what to start" \
    -pointsize 20 -fill "#$FGCONTAINER" -annotate +0+376 "Arch Linux" \
    -fill "#$TEXT" -annotate +0+426 "Arch Linux  (Plymouth)" -annotate +0+476 "Advanced" -annotate +0+526 "UEFI Firmware Settings" -annotate +0+576 "Restart" -annotate +0+626 "Shut down" \
    -fill "#$TEXTDIM" -pointsize 16 -annotate +0+908 "starting in 5 s, press any key to stay" "$out/grub-menu.png"
  # Plymouth: passphrase screen with 9 typed characters
  local P="$WORK/ply" cmd
  cmd=(magick "$P/bg.png" -resize 1920x1080! "$P/track.png" -geometry +860+440 -composite "$P/arc.png" -geometry +860+440 -composite "$P/dot.png" -geometry +951+531 -composite
       "$P/label.png" -geometry +740+632 -composite "$P/entry.png" -geometry +740+674 -composite)
  local i; for i in 0 1 2 3 4 5 6 7 8; do cmd+=("$P/bullet.png" -geometry +$((740 + 34 + i*22))+$((674 + 21)) -composite); done
  "${cmd[@]}" "$out/plymouth-passphrase.png"
  # raw assets for the live windows (boot-preview)
  mkdir -p "$out/gt" "$out/ply"; cp "$WORK"/gt/* "$out/gt/"; cp "$WORK"/ply/*.png "$out/ply/"
  cp "$WORK/card.png" "$WORK/pill.png" "$out/"; cp "$COLORS" "$out/colors.json"
  echo "wrote $out/grub-menu.png and $out/plymouth-passphrase.png (approximations: real GRUB/Plymouth rendering differs a little)"
}

backup() { [ -e "$1" ] && [ ! -e "$1.bak" ] && run cp -a "$1" "$1.bak" || true; }

# ================= commands =================
status() {
  detect
  say "this machine"
  echo "boot loader   : $LOADER  (${LOADER_INFO:-LoaderInfo not set})"
  echo "kernel images : $([ "$UKI" = 1 ] && echo "unified kernel image (UKI) in $UKI_DIR" || echo "classic initramfs")"
  echo "disk          : $(lsblk -no TYPE,FSTYPE 2>/dev/null | grep -q crypto_LUKS && echo "encrypted root (passphrase asked at boot)" || echo "not encrypted")"
  echo "plymouth      : $(pacman -Q plymouth 2>/dev/null || echo "not installed")"
  echo "cmdline       : $(cat /proc/cmdline)"
  say "what each step does"
  echo "splash   : rebuilds your UKI with a splash picture matching the lock screen (backup: *.efi.bak)."
  echo "plymouth : installs plymouth + a themed 'rice' spinner, builds ${UKI_DIR}/arch-linux-hardened-splash.efi as an extra entry (it shows up in the $LOADER menu)."
  echo "grub     : $([ "$LOADER" = grub ] && echo "GRUB is in use: writes /boot/grub/themes/rice and sets GRUB_THEME" || echo "skipped, your loader is $LOADER so a GRUB theme would do nothing")"
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
  say "building the 'rice' boot theme (wallpaper, spinner, passphrase entry)"
  make_plymouth_art "$WORK/ply"
  if [ "$DRY" = 1 ]; then echo "+ install theme files -> $T/rice ($(ls "$WORK/ply" | tr '\n' ' '))"; else
    rm -rf "$T/rice"; install -d "$T/rice"
    install -m644 "$WORK"/ply/*.png "$WORK/ply/rice.script" "$T/rice/"
    cat > "$T/rice/rice.plymouth" <<PLY
[Plymouth Theme]
Name=Rice
Description=Wallpaper-derived boot screen matching the lock screen
ModuleName=script

[script]
ImageDir=$T/rice
ScriptFile=$T/rice/rice.script
PLY
    plymouth-set-default-theme rice
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
  # the running command line, minus any earlier quiet/splash/loglevel, plus the quiet boot options
  echo "$(tr ' ' '\n' < /proc/cmdline | grep -v -e '^quiet$' -e '^splash$' -e '^loglevel=' -e '^vt.global_cursor_default=' | tr '\n' ' ') quiet splash loglevel=3 vt.global_cursor_default=0" > "$WORK/cmdline"
  say "building the extra entry (your normal entry is not touched)"
  run mkinitcpio -c /etc/mkinitcpio-splash.conf -k "$KVER_IMG" -U "$UKI_DIR/arch-linux-hardened-splash.efi" --cmdline "$WORK/cmdline" --splash /usr/share/systemd/bootctl/splash-rice.bmp
  cat <<MSG

done. Next:
  1. sudo bash boot-theme.sh grub     (rebuilds the menu so the entry shows up with a proper name)
  2. reboot and pick "Arch Linux  (Plymouth)"; type your disk passphrase and check you reach the login screen.
  3. if anything is wrong, boot the plain "Arch Linux" entry; nothing else was changed.
     remove the extra image with:  sudo rm $UKI_DIR/arch-linux-hardened-splash.efi
MSG
}

grubtheme() {
  detect
  if [ "$LOADER" != grub ]; then echo "GRUB does not look like your boot loader ($LOADER), so a GRUB theme would do nothing. Skipping."; return 0; fi
  D=/boot/grub/themes/rice
  say "building the GRUB theme"
  make_grub_art "$WORK/gt"
  run mkdir -p "$D"
  if [ "$DRY" = 1 ]; then echo "+ install theme files -> $D ($(ls "$WORK/gt" | wc -l) files)"; else rm -f "$D"/*; install -m644 "$WORK"/gt/* "$D/"; fi
  say "tidy menu: one entry per kernel image, extras under Advanced"
  # the stock generators (one entry per image plus firmware/boot-manager leftovers) are switched off, not deleted
  for g in 15_uki 25_bli 30_os-prober 31_efi_bootnext; do [ -e "/etc/grub.d/$g" ] && run chmod -x "/etc/grub.d/$g"; done
  if [ "$DRY" = 1 ]; then echo "+ write /etc/grub.d/15_rice and /etc/grub.d/99_rice, pacman hook /etc/pacman.d/hooks/rice-grub.hook"; else
    printf '%s' "$GRUB_ENTRIES_SCRIPT" > /etc/grub.d/15_rice; chmod 755 /etc/grub.d/15_rice
    printf '%s' "$GRUB_POWER_SCRIPT" > /etc/grub.d/99_rice;   chmod 755 /etc/grub.d/99_rice
    install -d /etc/pacman.d/hooks
    cat > /etc/pacman.d/hooks/rice-grub.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = grub

[Action]
Description = Keeping the stock GRUB entry generators off (rice menu)
When = PostTransaction
Exec = /usr/bin/chmod -x /etc/grub.d/15_uki /etc/grub.d/25_bli /etc/grub.d/30_os-prober /etc/grub.d/31_efi_bootnext
HOOK
  fi
  backup /etc/default/grub
  run sed -i -e '/^GRUB_THEME=/d' -e '/^#\?GRUB_DISABLE_OS_PROBER=/d' -e '/^GRUB_GFXMODE=/d' /etc/default/grub
  if [ "$DRY" = 1 ]; then echo "+ append GRUB_DISABLE_OS_PROBER=true, GRUB_GFXMODE=1920x1080,auto, GRUB_THEME to /etc/default/grub"; else
    printf '%s\n' 'GRUB_DISABLE_OS_PROBER=true' 'GRUB_GFXMODE=1920x1080,auto' "GRUB_THEME=\"$D/theme.txt\"" >> /etc/default/grub
  fi
  run grub-mkconfig -o /boot/grub/grub.cfg
  if [ "$DRY" = 0 ] && ! grep -q 'chainloader /EFI/Linux/arch-linux-hardened.efi' /boot/grub/grub.cfg; then
    echo "the new menu has no entry for arch-linux-hardened.efi: putting the stock entries back" >&2
    for g in 15_uki 25_bli 31_efi_bootnext; do [ -e "/etc/grub.d/$g" ] && chmod +x "/etc/grub.d/$g"; done
    rm -f /etc/grub.d/15_rice /etc/grub.d/99_rice
    grub-mkconfig -o /boot/grub/grub.cfg; exit 1
  fi
  [ "$DRY" = 1 ] || { echo; echo "menu entries now in grub.cfg:"; grep -E '^\s*(menuentry|submenu) ' /boot/grub/grub.cfg | sed 's/ --class.*//; s/{$//'; }
  cat <<MSG

done. Reboot to see it.
Undo: sudo cp /etc/default/grub.bak /etc/default/grub; sudo chmod +x /etc/grub.d/{15_uki,25_bli,31_efi_bootnext}; sudo rm /etc/grub.d/{15,99}_rice /etc/pacman.d/hooks/rice-grub.hook; sudo grub-mkconfig -o /boot/grub/grub.cfg
MSG
}

case "$CMD" in
  status) status ;;
  splash) splash ;;
  plymouth) plymouth ;;
  grub) grubtheme ;;
  preview) preview "${1:-}" ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
