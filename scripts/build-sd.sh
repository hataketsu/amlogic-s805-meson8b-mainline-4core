#!/usr/bin/env bash
# Partition + populate an SD card: FAT boot (uImage/dtb/uInitrd) + ext4 rootfs (LABEL=ARMROOT).
# Usage: sudo ./build-sd.sh /dev/sdX  [rootfs-dir]
# WARNING: destroys /dev/sdX. Make sure it's the SD card (check `lsblk` first).
set -euo pipefail
DEV=${1:?usage: build-sd.sh /dev/sdX [rootfs-dir]}
ROOTFS=${2:-rootfs}                 # an armhf rootfs (debootstrap bookworm) with /usr/lib/modules
KVER=${KVER:-6.1.174}
HERE="$(cd "$(dirname "$0")/.." && pwd)"

[ -b "$DEV" ] || { echo "$DEV not a block device"; exit 1; }
echo "About to ERASE $DEV ($(lsblk -dno SIZE "$DEV")). Ctrl-C to abort."; read -r _

umount "${DEV}"* 2>/dev/null || true
wipefs -a "$DEV"
sfdisk "$DEV" <<'PART'
label: dos
2048,524288,c,*
,,L
PART
partprobe "$DEV"; sleep 2
P1="${DEV}1"; P2="${DEV}2"; [ -b "${DEV}p1" ] && { P1="${DEV}p1"; P2="${DEV}p2"; }
mkfs.vfat -n BOOT "$P1"
mkfs.ext4 -q -L ARMROOT "$P2"

mkdir -p /mnt/_b /mnt/_r
mount "$P1" /mnt/_b; mount "$P2" /mnt/_r
# boot files (4-core: use the tz dtb)
cp "$HERE/uImage"  /mnt/_b/uImage
cp "$HERE/uInitrd" /mnt/_b/uInitrd
dtc -I dts -O dtb -o /mnt/_b/dtb "$HERE/dtb/meson8b-m201-tz.dts"
# rootfs + matching modules
rsync -aHAX --numeric-ids "$ROOTFS"/ /mnt/_r/
rm -rf /mnt/_r/usr/lib/modules/$KVER
cp -a "$HERE/modout/lib/modules/$KVER" /mnt/_r/usr/lib/modules/
depmod -b /mnt/_r "$KVER"
cat > /mnt/_r/etc/fstab <<'F'
LABEL=ARMROOT / ext4 defaults,noatime,errors=remount-ro 0 1
LABEL=BOOT /boot vfat defaults,nofail 0 2
F
sync; umount /mnt/_b /mnt/_r
echo "SD ready. In u-boot set bootcmd (note: NO nosmp for 4 cores):"
cat <<'UB'
setenv bootcmd 'setenv bootargs console=ttyAML0,115200n8 rootwait rw; mmc rescan 0; fatload mmc 0 0x11000000 uImage; fatload mmc 0 0x12000000 uInitrd; fatload mmc 0 0x10000000 dtb; bootm 0x11000000 0x12000000 0x10000000'
saveenv
reset
UB
