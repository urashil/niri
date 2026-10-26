#!/usr/bin/env bash
# switch-to-grub.sh: make GRUB the boot menu if the machine is booting something else (systemd-boot).
# If you are already booting with GRUB this does NOTHING.
#
# Which loader is running is read from the firmware variable "LoaderInfo", which every boot loader sets
# ("GRUB 2.16", "systemd-boot 257", ...). The firmware entry names are not reliable for this.
#
# Why this is low risk on a unified-kernel-image (UKI) setup: GRUB 2.14+ finds the UKIs on the EFI partition by
# itself (/etc/grub.d/15_uki + the `uki` command) and starts them. The image carries its own initramfs and kernel
# command line, so GRUB never has to read the encrypted disk and the way Arch boots does not change.
#
# What it does, in order, stopping WITHOUT changing the boot order if a step fails:
#   1. checks: UEFI, Secure Boot off, FAT EFI partition on /boot, UKIs present, GRUB with UKI support installed
#   2. saves the firmware boot order and writes a rollback script to /root/boot-switch-backup/
#   3. installs GRUB next to the current loader (its own folder and firmware entry; \EFI\BOOT\BOOTX64.EFI is not touched)
#   4. builds grub.cfg and checks it contains the UKI entry
#   5. only then puts GRUB first in the firmware boot order (the old entries stay behind it)
#
#   sudo bash switch-to-grub.sh [--dry-run]        SKIP_GRUB=1 skips it when deps.sh calls it
set -uo pipefail

DRY=0; for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=1; done
ESP=/boot
BACKUP=/root/boot-switch-backup
say()  { printf '\n==> %s\n' "$*"; }
run()  { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }
skip() { echo; echo "boot loader: $*"; exit 0; }
stop() { echo; echo "GRUB switch STOPPED: $*" >&2; echo "The firmware boot order was NOT changed, so the machine boots exactly as before." >&2; exit 1; }
warn() { echo "   note: $*"; }

[ "${SKIP_GRUB:-0}" = 1 ] && skip "SKIP_GRUB=1, leaving it alone"
if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then echo "run with sudo (or add --dry-run)" >&2; exit 1; fi

# ---------- which loader is running now? ----------
[ -d /sys/firmware/efi ] || skip "not a UEFI boot, nothing to do"
INFO=$(tail -c +5 /sys/firmware/efi/efivars/LoaderInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\0' || true)
# the rice menu entries start the image directly, so GRUB no longer sets LoaderInfo; its own menu marks it
[ -z "$INFO" ] && { [ -e /etc/grub.d/15_rice ] || [ -f /boot/grub/grub.cfg ]; } && INFO="GRUB (rice menu)"
say "boot loader check"
echo "running loader: ${INFO:-unknown}"
case "$INFO" in
  GRUB*) skip "you are already booting with GRUB ($INFO). Nothing to change." ;;
  "")    skip "cannot tell which loader started this boot (no LoaderInfo variable). Not touching anything." ;;
  systemd-boot*) echo "systemd-boot is running; switching to GRUB (the old loader stays installed as a fallback)." ;;
  *)     skip "running loader is '$INFO', not something this script knows how to replace. Not touching anything." ;;
esac
say "GRUB switch$([ "$DRY" = 1 ] && echo ' (dry run: nothing is changed)')"

# ---------- 1. checks ----------
[ "$(findmnt -n -o FSTYPE "$ESP" 2>/dev/null)" = vfat ] || skip "$ESP is not a FAT EFI partition"
sb=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | awk '{print $NF}')
[ "$sb" = 1 ] && skip "Secure Boot is on (an unsigned GRUB would not start)"
command -v efibootmgr >/dev/null || { [ "$DRY" = 1 ] && warn "efibootmgr missing (installed on a real run)" || run pacman -S --needed --noconfirm efibootmgr; }
command -v grub-install >/dev/null || { [ "$DRY" = 1 ] && warn "grub missing (installed on a real run)" || run pacman -S --needed --noconfirm grub; }
[ -x /etc/grub.d/15_uki ] || skip "this GRUB has no UKI support (/etc/grub.d/15_uki); needs grub 2.14 or newer"
[ -f /usr/lib/grub/x86_64-efi/blsuki.mod ] || skip "this GRUB has no UKI module (blsuki.mod)"
if ls "$ESP"/EFI/Linux/*.efi >/dev/null 2>&1; then :; elif [ "$DRY" = 1 ]; then warn "cannot look inside $ESP as a normal user; a real run checks for the UKIs"; else skip "no unified kernel images in $ESP/EFI/Linux"; fi
avail=$(df --output=avail -m "$ESP" | tail -1 | tr -d ' ')
[ "${avail:-0}" -gt 40 ] || stop "only ${avail}MB free on the EFI partition"

# ---------- 2. backup ----------
say "saving the current boot setup to $BACKUP"
run mkdir -p "$BACKUP"
OLD_ORDER=$(efibootmgr 2>/dev/null | awk -F': ' '/^BootOrder/{print $2}')
echo "boot order now: $OLD_ORDER"
if [ "$DRY" = 0 ]; then
  efibootmgr -v > "$BACKUP/efibootmgr-before.txt" 2>&1
  echo "$OLD_ORDER" > "$BACKUP/boot-order-before.txt"
  [ -f /etc/default/grub ] && cp -a /etc/default/grub "$BACKUP/etc-default-grub"
fi

# ---------- 3. install ----------
say "installing GRUB to $ESP/EFI/GRUB (own folder, own firmware entry)"
# the stock kernel entries would boot a kernel without an initramfs and would sort BEFORE the UKI entry
if [ -x /etc/grub.d/10_linux ]; then run chmod -x /etc/grub.d/10_linux; CHMOD10=1; else CHMOD10=0; fi
grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub 2>/dev/null || run sh -c "echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub"
run grub-install --target=x86_64-efi --efi-directory="$ESP" --bootloader-id=GRUB
[ "$DRY" = 1 ] || [ -f "$ESP/EFI/GRUB/grubx64.efi" ] || stop "grub-install did not produce $ESP/EFI/GRUB/grubx64.efi"

# ---------- 4. config + check ----------
say "building the menu"
run grub-mkconfig -o "$ESP/grub/grub.cfg"
if [ "$DRY" = 0 ]; then
  grep -qE '^[[:space:]]*uki[[:space:]]*$' "$ESP/grub/grub.cfg" || stop "the generated menu has no UKI entry"
  echo "menu OK: contains the UKI entry"
fi

# ---------- 5. boot order ----------
say "making GRUB the first firmware boot entry (the old entries stay behind it)"
if [ "$DRY" = 1 ]; then
  echo "+ efibootmgr -o <GRUB entry>,$OLD_ORDER"
else
  num=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\* GRUB$/\1/p' | head -1)
  [ -n "$num" ] || stop "grub-install did not create a 'GRUB' firmware entry (the kernel may block writing EFI variables)"
  rest=$(echo "$OLD_ORDER" | tr ',' '\n' | grep -v "^$num$" | paste -sd, -)
  efibootmgr -o "$num${rest:+,$rest}" >/dev/null || stop "could not change the boot order"
  efibootmgr | grep '^BootOrder'
  cat > "$BACKUP/rollback.sh" <<ROLL
#!/usr/bin/env bash
# puts the firmware boot order back and removes the GRUB firmware entry (files on the EFI partition are left)
efibootmgr -o $OLD_ORDER
efibootmgr -B -b $num
$([ "$CHMOD10" = 1 ] && echo "chmod +x /etc/grub.d/10_linux")
echo "rolled back: the machine boots through the previous entries again"
ROLL
  chmod 700 "$BACKUP/rollback.sh"
fi

# ---------- optional: the matching theme ----------
THEME="$(dirname "$(readlink -f "$0")")/boot-theme.sh"
if [ "$DRY" = 0 ] && [ -f "$THEME" ]; then
  say "applying the lock-screen theme to GRUB"
  bash "$THEME" grub || echo "   (theme step failed; the plain GRUB menu still works)"
fi

cat <<MSG

done. The next boot shows a GRUB menu with your Arch kernel image(s). If anything looks wrong:
  * press F12 at the firmware logo and pick the old entry, or
  * run: sudo bash $BACKUP/rollback.sh
MSG
